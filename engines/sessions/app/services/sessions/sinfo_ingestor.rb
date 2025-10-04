require 'set'

module Sessions
  class SinfoIngestor
    SCHEMA = (ENV['PG_SCHEMA'].presence || 'octo').freeze
    STATES = %w[alloc idle comp drain drng down maint reserved mix].freeze

    def initialize(raw_text:, source_cmd: 'sinfo -a', parser_version: 'v1', quiet: false, **_)
      @raw = raw_text.to_s
      @source_cmd = source_cmd
      @parser_version = parser_version
      @quiet = quiet
    end

    def call
      raise "empty sinfo output" if @raw.strip.empty?

      with_schema_context do
        with_silenced_ar do
          ensure_schema!            
          ensure_enum_and_tables!  

          snapshot_id = insert_snapshot!

          parsed_lines   = parse_table_lines(@raw)
          partition_names = parsed_lines.map { |h| h[:partition] }.to_set
          hostnames       = parsed_lines.flat_map { |h| h[:hostnames] }.to_set

          part_id = upsert_partitions(partition_names, parsed_lines)
          node_id = upsert_nodes(hostnames)

          rows = []
          parsed_lines.each do |h|
            p_id = part_id[h[:partition]]
            st   = h[:state]
            rsn  = h[:has_reason]
            h[:hostnames].each do |hn|
              n_id = node_id[hn]
              rows << [snapshot_id, n_id, p_id, st, rsn]
            end
          end

          rows_written = bulk_upsert_node_states(rows)

          {
            snapshot_id: snapshot_id,
            nodes_total: hostnames.size,
            rows_written: rows_written,
            partitions: part_id.size,
            schema: SCHEMA
          }
        end
      end
    end

    private

    def with_silenced_ar
      return yield unless @quiet
      ar_logger  = ActiveRecord::Base.logger
      app_logger = defined?(Rails) ? Rails.logger : nil
      old_ar = ar_logger&.level
      old_app = app_logger&.level
      begin
        ar_logger.level  = Logger::WARN if ar_logger
        app_logger.level = Logger::INFO if app_logger
        yield
      ensure
        ar_logger.level  = old_ar if ar_logger
        app_logger.level = old_app if app_logger
      end
    end

    def with_schema_context
      ActiveRecord::Base.connection_pool.with_connection { yield }
    end

    def ensure_schema!
      ActiveRecord::Base.connection.execute(%(CREATE SCHEMA IF NOT EXISTS #{quoted_ident(SCHEMA)};))
    end

    def ensure_enum_and_tables!
      conn = ActiveRecord::Base.connection

      conn.execute(<<~SQL)
        DO $$
        BEGIN
          IF NOT EXISTS (
            SELECT 1
            FROM pg_type t
            JOIN pg_namespace n ON n.oid = t.typnamespace
            WHERE t.typname = 'slurm_node_state' AND n.nspname = '#{SCHEMA}'
          ) THEN
            EXECUTE 'CREATE TYPE #{qualified('slurm_node_state')} AS ENUM (#{STATES.map { |s| "'#{s}'" }.join(', ')})';
          END IF;
        END;
        $$;
      SQL

      conn.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS #{qualified('slurm_partitions')} (
          id         SERIAL PRIMARY KEY,
          name       TEXT UNIQUE NOT NULL,
          time_limit TEXT
        );
      SQL

      conn.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS #{qualified('slurm_snapshots')} (
          id              BIGSERIAL PRIMARY KEY,
          captured_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          source_cmd      TEXT NOT NULL DEFAULT 'sinfo -a',
          raw_text        TEXT NOT NULL,
          parser_version  TEXT NOT NULL DEFAULT 'v1'
        );
      SQL

      conn.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS #{qualified('slurm_nodes')} (
          id        BIGSERIAL PRIMARY KEY,
          hostname  TEXT UNIQUE NOT NULL,
          prefix    TEXT NOT NULL,
          number    INT
        );
      SQL

      conn.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS #{qualified('slurm_node_snapshot')} (
          snapshot_id   BIGINT NOT NULL REFERENCES #{qualified('slurm_snapshots')}(id) ON DELETE CASCADE,
          node_id       BIGINT NOT NULL REFERENCES #{qualified('slurm_nodes')}(id)     ON DELETE RESTRICT,
          partition_id  INT    NOT NULL REFERENCES #{qualified('slurm_partitions')}(id) ON DELETE RESTRICT,
          state         #{qualified('slurm_node_state')} NOT NULL,
          has_reason    BOOLEAN NOT NULL DEFAULT FALSE,
          PRIMARY KEY (snapshot_id, node_id)
        );
      SQL

      ensure_index!('slurm_snapshots',     'idx_slurm_snapshots_captured_at',   'captured_at DESC')
      ensure_index!('slurm_node_snapshot', 'idx_node_snapshot_partition_state', 'partition_id, state')
      ensure_index!('slurm_nodes',         'idx_slurm_nodes_prefix_number',     'prefix, number')
    end

    def ensure_index!(table, name, columns_sql)
      ActiveRecord::Base.connection.execute(<<~SQL)
        DO $$
        BEGIN
          IF NOT EXISTS (
            SELECT 1
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE c.relkind='i'
              AND c.relname='#{name}'
              AND n.nspname='#{SCHEMA}'
          ) THEN
            EXECUTE 'CREATE INDEX #{name} ON #{qualified(table)} (#{columns_sql})';
          END IF;
        END;
        $$;
      SQL
    end

    def qualified(name) = %("#{SCHEMA}".#{name})
    def quoted_ident(name) = %("#{name}")

    def insert_snapshot!
      sql = <<~SQL
        INSERT INTO #{qualified('slurm_snapshots')} (captured_at, source_cmd, raw_text, parser_version)
        VALUES (NOW(), $1, $2, $3)
        RETURNING id
      SQL
      res = ActiveRecord::Base.connection.exec_query(sql, 'SQL', [
        bind_str(@source_cmd),
        bind_str(@raw),
        bind_str(@parser_version)
      ])
      res.rows.first.first
    end

    def upsert_partitions(partition_names, parsed_lines)
      limits = {}
      parsed_lines.each { |h| limits[h[:partition]] ||= h[:timelimit] }

      map = {}
      partition_names.each_slice(100) do |chunk|
        values = []
        binds  = []
        chunk.each_with_index do |name, i|
          tl = limits[name]
          values << "($#{i*2+1}, $#{i*2+2})"
          binds << bind_str(name) << bind_str(tl)
        end

        sql = <<~SQL
          INSERT INTO #{qualified('slurm_partitions')} (name, time_limit)
          VALUES #{values.join(',')}
          ON CONFLICT (name) DO UPDATE SET time_limit = EXCLUDED.time_limit
          RETURNING id, name
        SQL
        res = ActiveRecord::Base.connection.exec_query(sql, 'SQL', binds)
        res.rows.each { |(id, name)| map[name] = id }
      end
      map
    end

    def upsert_nodes(hostnames)
      map = {}
      hostnames.each_slice(500) do |chunk|
        values = []
        binds  = []
        chunk.each_with_index do |hn, i|
          prefix, number = split_prefix_number(hn)
          values << "($#{i*3+1}, $#{i*3+2}, $#{i*3+3})"
          binds << bind_str(hn) << bind_str(prefix) << bind_int(number)
        end

        sql = <<~SQL
          INSERT INTO #{qualified('slurm_nodes')} (hostname, prefix, number)
          VALUES #{values.join(',')}
          ON CONFLICT (hostname) DO UPDATE
            SET prefix = EXCLUDED.prefix, number = EXCLUDED.number
          RETURNING id, hostname
        SQL
        res = ActiveRecord::Base.connection.exec_query(sql, 'SQL', binds)
        res.rows.each { |(id, hostname)| map[hostname] = id }
      end
      map
    end

    def bulk_upsert_node_states(rows)
      return 0 if rows.empty?

      count = 0
      rows.each_slice(5_000) do |chunk|
        values = []
        binds  = []
        chunk.each_with_index do |(snap_id, node_id, part_id, state, has_reason), i|
          base = i * 5
          values << "($#{base+1}, $#{base+2}, $#{base+3}, $#{base+4}::#{qualified('slurm_node_state')}, $#{base+5})"
          binds  << bind_int(snap_id) << bind_int(node_id) << bind_int(part_id) \
                  << bind_str(state)  << bind_bool(has_reason)
        end

        sql = <<~SQL
          INSERT INTO #{qualified('slurm_node_snapshot')}
            (snapshot_id, node_id, partition_id, state, has_reason)
          VALUES #{values.join(',')}
          ON CONFLICT (snapshot_id, node_id) DO UPDATE
            SET partition_id = EXCLUDED.partition_id,
                state        = EXCLUDED.state,
                has_reason   = EXCLUDED.has_reason
        SQL
        ActiveRecord::Base.connection.exec_query(sql, 'SQL', binds)
        count += chunk.size
      end
      count
    end

    def parse_table_lines(raw)
      lines = raw.split("\n").map!(&:rstrip)
      start_idx = lines.index { |l| l.strip.start_with?('PARTITION') } || 0
      rows = lines[(start_idx + 1)..] || []
      rows.filter_map { |line| parse_line(line) }
    end

    def parse_line(line)
      m = line.strip.match(/^(\S+)\s+(\S+)\s+(\S+)\s+(\d+)\s+(\S+)\s+(.+)$/)
      return nil unless m
      raw_partition, avail, timelimit, _nodes_count, state_token, nodelist_raw = m.captures
      partition = raw_partition.sub(/\*$/, '')
      state, has_reason = parse_state(state_token)
      hostnames = expand_nodelist(nodelist_raw)
      {
        partition:  partition,
        avail:      avail,
        timelimit:  timelimit,
        state:      state,
        has_reason: has_reason,
        hostnames:  hostnames
      }
    end

    def parse_state(token)
      has_reason = token.end_with?('*')
      base = has_reason ? token[0..-2] : token
      state = STATES.include?(base) ? base : base
      [state, has_reason]
    end

    def expand_nodelist(nodelist_raw)
      str = nodelist_raw.strip
      return str.split(',').map(&:strip).reject(&:empty?) unless str.include?('[')
      result = []
      i = 0
      while i < str.length
        if str[i] == ','
          i += 1
          next
        end
        bracket_pos = str.index('[', i)
        if bracket_pos.nil?
          rest = str[i..-1]
          rest.split(',').each { |s| s = s.strip; result << s unless s.empty? }
          break
        end
        prefix = str[i...bracket_pos]
        close_pos = str.index(']', bracket_pos + 1)
        raise "bad NODELIST: missing ]" unless close_pos
        inner = str[(bracket_pos + 1)...close_pos]
        result.concat(expand_bracket_group(prefix, inner))
        i = close_pos + 1
      end
      result
    end

    def expand_bracket_group(prefix, inner)
      out = []
      inner.split(',').map(&:strip).reject(&:empty?).each do |part|
        if part.include?('-')
          a, b = part.split('-', 2).map!(&:strip)
          width = (a =~ /^\d+$/) ? a.length : nil
          (a.to_i..b.to_i).each do |x|
            num = width ? x.to_s.rjust(width, '0') : x.to_s
            out << "#{prefix}#{num}"
          end
        else
          out << "#{prefix}#{part}"
        end
      end
      out
    end

    def split_prefix_number(hostname)
      m = hostname.match(/^([^\d]*)(\d+)?$/)
      return [hostname, nil] unless m
      prefix = m[1] || ''
      number = m[2] ? m[2].to_i : nil
      [prefix, number]
    end

    def bind_str(val)
      ActiveRecord::Relation::QueryAttribute.new(nil, val, ActiveRecord::Type::String.new)
    end
    def bind_int(val)
      ActiveRecord::Relation::QueryAttribute.new(nil, val, ActiveRecord::Type::Integer.new)
    end
    def bind_bool(val)
      ActiveRecord::Relation::QueryAttribute.new(nil, val, ActiveRecord::Type::Boolean.new)
    end
  end
end

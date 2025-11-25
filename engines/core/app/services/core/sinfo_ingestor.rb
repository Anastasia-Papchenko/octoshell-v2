require "set"

module Core
  class SinfoIngestor
    TABLE_SYSTEMS     = 'core_analytics_systems'.freeze
    TABLE_SNAPSHOTS   = 'core_analytics_snapshots'.freeze
    TABLE_PARTITIONS  = 'core_analytics_partitions'.freeze
    TABLE_NODES       = 'core_analytics_nodes'.freeze
    TABLE_NODE_STATES = 'core_analytics_node_states'.freeze

    STATES = %w[alloc idle comp drain drng down maint reserved mix].freeze

    def initialize(raw_text:, source_cmd: 'sinfo -a', parser_version: 'v1',
                   quiet: false, system_slug: 'default', system_id: nil, **_)
      @raw            = raw_text.to_s
      @source_cmd     = source_cmd
      @parser_version = parser_version
      @quiet          = quiet
      @system_slug    = system_slug
      @system_id      = system_id
    end

    def call
      raise "empty sinfo output" if @raw.strip.empty?

      with_schema_context do
        with_silenced_ar do
          @system_id ||= ensure_system!(@system_slug)

          snapshot_id     = insert_snapshot!
          parsed_lines    = parse_table_lines(@raw)
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

          rows = rows.reverse.uniq { |snap_id, node_id, _p, _s, _r| [snap_id, node_id] }.reverse
          rows_written = bulk_upsert_node_states(rows)

          {
            snapshot_id:  snapshot_id,
            nodes_total:  hostnames.size,
            rows_written: rows_written,
            partitions:   part_id.size
          }
        end
      end
    end

    private

    def ensure_system!(slug)
      sql = <<~SQL
        INSERT INTO #{TABLE_SYSTEMS} (name, slug, created_at, updated_at)
        VALUES ($1, $2, NOW(), NOW())
        ON CONFLICT (slug) DO UPDATE
          SET updated_at = EXCLUDED.updated_at
        RETURNING id
      SQL
      res = ActiveRecord::Base.connection.exec_query(sql, 'SQL', [
        bind_str("System #{slug}"),
        bind_str(slug)
      ])
      res.rows.first.first
    end

    def with_silenced_ar
      return yield unless @quiet

      ar_logger  = ActiveRecord::Base.logger
      app_logger = defined?(Rails) ? Rails.logger : nil
      old_ar  = ar_logger&.level
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

    def insert_snapshot!
      sql = <<~SQL
        INSERT INTO #{TABLE_SNAPSHOTS}
          (system_id, captured_at, source_cmd, raw_text, parser_version, created_at, updated_at)
        VALUES ($1, NOW(), $2, $3, $4, NOW(), NOW())
        RETURNING id
      SQL
      res = ActiveRecord::Base.connection.exec_query(sql, 'SQL', [
        bind_int(@system_id),
        bind_str(@source_cmd),
        bind_str(@raw),
        bind_str(@parser_version)
      ])
      res.rows.first.first
    end


    def column_exists_in_db?(table, column)
      ActiveRecord::Base.connection.columns(table).any? { |c| c.name == column.to_s }
    end


    def upsert_partitions(partition_names, parsed_lines)
      has_time_limit = column_exists_in_db?(TABLE_PARTITIONS, :time_limit)

      limits = {}
      parsed_lines.each { |h| limits[h[:partition]] ||= h[:timelimit] }

      map = {}
      partition_names.each_slice(100) do |chunk|
        values = []
        binds  = []

        stride = has_time_limit ? 3 : 2
        chunk.each_with_index do |name, i|
          tl   = limits[name]
          base = i * stride
          values << "($#{base+1}, $#{base+2}#{has_time_limit ? ", $#{base+3}" : ""}, NOW(), NOW())"
          binds  << bind_int(@system_id) << bind_str(name)
          binds  << bind_str(tl) if has_time_limit
        end

        cols_arr = %w[system_id name]
        cols_arr << 'time_limit' if has_time_limit
        cols_arr += %w[created_at updated_at]
        cols = cols_arr.join(', ')

        set_clauses = []
        set_clauses << "time_limit = EXCLUDED.time_limit" if has_time_limit
        set_clauses << "updated_at = EXCLUDED.updated_at"

        sql = <<~SQL
          INSERT INTO #{TABLE_PARTITIONS} (#{cols})
          VALUES #{values.join(',')}
          ON CONFLICT (system_id, name) DO UPDATE
            SET #{set_clauses.join(', ')}
          RETURNING id, name
        SQL

        res = ActiveRecord::Base.connection.exec_query(sql, 'SQL', binds)
        res.rows.each { |(id, name)| map[name] = id }
      end

      map
    end

    def upsert_nodes(hostnames)
      has_number = column_exists_in_db?(TABLE_NODES, :number)

      map = {}
      hostnames.each_slice(500) do |chunk|
        values = []
        binds  = []

        stride = has_number ? 4 : 3
        chunk.each_with_index do |hn, i|
          prefix, number = split_prefix_number(hn)
          base = i * stride
          # system_id, hostname, prefix, [number], created_at, updated_at
          values << "($#{base+1}, $#{base+2}, $#{base+3}#{has_number ? ", $#{base+4}" : ""}, NOW(), NOW())"
          binds  << bind_int(@system_id) << bind_str(hn) << bind_str(prefix)
          binds  << bind_int(number) if has_number
        end

        cols_arr = %w[system_id hostname prefix]
        cols_arr << 'number' if has_number
        cols_arr += %w[created_at updated_at]
        cols = cols_arr.join(', ')

        set_clauses = ["prefix = EXCLUDED.prefix"]
        set_clauses << "number = EXCLUDED.number" if has_number
        set_clauses << "updated_at = EXCLUDED.updated_at"

        sql = <<~SQL
          INSERT INTO #{TABLE_NODES} (#{cols})
          VALUES #{values.join(',')}
          ON CONFLICT (system_id, hostname) DO UPDATE
            SET #{set_clauses.join(', ')}
          RETURNING id, hostname
        SQL

        res = ActiveRecord::Base.connection.exec_query(sql, 'SQL', binds)
        res.rows.each { |(id, hostname)| map[hostname] = id }
      end

      map
    end

    def bulk_upsert_node_states(rows)
      return 0 if rows.empty?

      node_ids = rows.map { |(_snap_id, node_id, _p, _s, _r)| node_id }.uniq

      current_states = load_current_states(node_ids)

      rows_to_insert = []
      ids_to_close   = []

      rows.each do |snap_id, node_id, part_id, state, has_reason|
        cur = current_states[node_id]

        if cur.nil?
          rows_to_insert << [snap_id, node_id, part_id, state, has_reason]
        else
          if cur[:partition_id] == part_id &&
             cur[:state]        == state &&
             cur[:has_reason]   == has_reason
            next
          else
            ids_to_close << cur[:id]
            rows_to_insert << [snap_id, node_id, part_id, state, has_reason]
          end
        end
      end

      close_node_states(ids_to_close) unless ids_to_close.empty?

      insert_new_node_states(rows_to_insert)
    end

    def load_current_states(node_ids)
      return {} if node_ids.empty?

      map = {}

      node_ids.each_slice(5_000) do |chunk|
        placeholders = (1..chunk.size).map { |i| "$#{i+1}" }.join(', ')
        sql = <<~SQL
          SELECT id, node_id, partition_id, state, has_reason
          FROM #{TABLE_NODE_STATES}
          WHERE system_id = $1
            AND valid_to IS NULL
            AND node_id IN (#{placeholders})
        SQL

        binds = [bind_int(@system_id)]
        chunk.each { |nid| binds << bind_int(nid) }

        res = ActiveRecord::Base.connection.exec_query(sql, 'SQL', binds)
        res.rows.each do |id, node_id, part_id, state, has_reason|
          map[node_id] = {
            id:           id,
            partition_id: part_id,
            state:        state,
            has_reason:   has_reason
          }
        end
      end

      map
    end

    def close_node_states(ids)
      ids.each_slice(5_000) do |chunk|
        placeholders = (1..chunk.size).map { |i| "$#{i}" }.join(', ')
        sql = <<~SQL
          UPDATE #{TABLE_NODE_STATES}
          SET valid_to   = NOW(),
              updated_at = NOW()
          WHERE id IN (#{placeholders})
        SQL
        binds = chunk.map { |id| bind_int(id) }
        ActiveRecord::Base.connection.exec_query(sql, 'SQL', binds)
      end
    end

    def insert_new_node_states(rows)
      return 0 if rows.empty?

      count = 0
      rows.each_slice(5_000) do |chunk|
        values = []
        binds  = []

        chunk.each_with_index do |(snap_id, node_id, part_id, state, has_reason), i|
          base = i * 6
          values << "($#{base+1}, $#{base+2}, $#{base+3}, $#{base+4}, $#{base+5}, NULL, $#{base+6}, NOW(), NULL, NOW(), NOW())"
          binds  << bind_int(@system_id) << bind_int(snap_id) << bind_int(node_id) \
                  << bind_int(part_id)   << bind_str(state)   << bind_bool(has_reason)
        end

        sql = <<~SQL
          INSERT INTO #{TABLE_NODE_STATES}
            (system_id, snapshot_id, node_id, partition_id,
             state, substate, has_reason, valid_from, valid_to, created_at, updated_at)
          VALUES #{values.join(',')}
          ON CONFLICT (snapshot_id, node_id) DO UPDATE
            SET partition_id = EXCLUDED.partition_id,
                state        = EXCLUDED.state,
                has_reason   = EXCLUDED.has_reason,
                updated_at   = EXCLUDED.updated_at
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
          rest.split(',').each do |s|
            s = s.strip
            result << s unless s.empty?
          end
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

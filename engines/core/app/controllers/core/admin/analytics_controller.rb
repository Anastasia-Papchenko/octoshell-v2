module Core
  class Admin::AnalyticsController < Admin::ApplicationController
    # skip_before_action :authorize_admins, only: [:index, :sinfo, :create_comment], raise: false
    before_action :require_analytics_access
    before_action :octo_authorize!
    octo_use(:project_class, :core, 'Project')

    before_action :prepare_comments, only: [:index, :create_comment, :sinfo]

    def index
      @total_reports     = 0
      @submitted_reports = 0
      @assessing_reports = 0
      @rejected_reports  = 0

      @clusters = Core::Cluster.order(:name_ru).includes(:nodes)

      node_states_rel = Core::Analytics::NodeState.current
      @global_state_counts = node_states_rel.group(:state).count

      @cluster_stats = {}
      @clusters.each do |cluster|
        @cluster_stats[cluster.id] = {
          total_nodes: cluster.nodes.size,
          states:      Hash.new(0),
          issues:      0
        }
      end

      states_counts = node_states_rel.group(:cluster_id, :state).count
      states_counts.each do |(cluster_id, state), count|
        next unless @cluster_stats.key?(cluster_id)
        @cluster_stats[cluster_id][:states][state] = count
      end

      issues_counts = node_states_rel.where(has_reason: true).group(:cluster_id).count
      issues_counts.each do |cluster_id, count|
        next unless @cluster_stats.key?(cluster_id)
        @cluster_stats[cluster_id][:issues] = count
      end

      @partition_stats = {}
      partition_counts = node_states_rel.joins(:partition)
                                        .group(
                                          'core_partitions.cluster_id',
                                          'core_partitions.id',
                                          'core_partitions.name',
                                          'core_analytics_node_states.state'
                                        ).count

      partition_counts.each do |(cluster_id, partition_id, partition_name, state), count|
        @partition_stats[cluster_id] ||= {}
        @partition_stats[cluster_id][partition_id] ||= {
          name:   partition_name,
          states: Hash.new(0)
        }
        @partition_stats[cluster_id][partition_id][:states][state] = count
      end

      @latest_snapshots = Core::Analytics::Snapshot.latest_first.includes(:cluster).limit(10)
      @snapshot_stats   = {}

      if @latest_snapshots.any?
        snapshot_ids = @latest_snapshots.map(&:id)
        snapshot_counts = Core::Analytics::NodeState.where(snapshot_id: snapshot_ids)
                                                   .group(:snapshot_id, :state)
                                                   .count
        snapshot_counts.each do |(snap_id, state), count|
          @snapshot_stats[snap_id] ||= {}
          @snapshot_stats[snap_id][state] = count
        end
      end

      @active_tab ||= 'analytics'
    end

    def availability
      @clusters = Core::Cluster.order(:name_ru).includes(:nodes)

      @from   = parse_time(params[:from]) || 7.days.ago
      @to     = parse_time(params[:to])   || Time.current
      @metric = params[:metric].presence || 'idle' # idle | work | up

      @active_tab = 'availability'
    end

    def availability_data
      cluster = Core::Cluster.find(params[:cluster_id])

      from   = parse_time(params[:from]) || 7.days.ago
      to     = parse_time(params[:to])   || Time.current
      metric = params[:metric].presence || 'idle'

      total_nodes = cluster.nodes.size

      snaps = cluster.snapshots
                     .where(captured_at: from..to)
                     .order(:captured_at)
                     .limit(2000)

      snap_ids = snaps.map(&:id)

      counts =
        if snap_ids.any?
          Core::Analytics::NodeState
            .where(snapshot_id: snap_ids)
            .group(:snapshot_id, :state)
            .count
        else
          {}
        end

      unavailable_states = %w[down drain drng maint reserved].freeze

      points = snaps.map do |s|
        idle  = counts[[s.id, 'idle']].to_i
        alloc = counts[[s.id, 'alloc']].to_i
        unavailable = unavailable_states.sum { |st| counts[[s.id, st]].to_i }

        y =
          case metric
          when 'work' then (alloc + idle)
          when 'up'   then [total_nodes - unavailable, 0].max
          else idle
          end

        { x: s.captured_at.iso8601, y: y }
      end

      comments = cluster.comments
                        .where('valid_from <= ? AND (valid_to IS NULL OR valid_to >= ?)', to, from)
                        .order(:valid_from)
                        .limit(500)
                        .map do |c|
                          {
                            from: c.valid_from.iso8601,
                            to: (c.valid_to || to).iso8601,
                            severity: c.severity.to_s,
                            title: c.title.to_s,
                            nodes_count: c.nodes.size
                          }
                        end

      render json: {
        cluster_id: cluster.id,
        total_nodes: total_nodes,
        metric: metric,
        from: from.iso8601,
        to: to.iso8601,
        points: points,
        comments: comments
      }
    end

    def sinfo
      cluster_id = params[:cluster_id].presence
      raise ArgumentError, "cluster_id is required" if cluster_id.blank?

      cluster = Core::Cluster.find(cluster_id)

      fetcher = Core::SinfoFetcher.new(
        host: cluster.host,
        user: (cluster.admin_login.presence || ENV.fetch("HPC_USER", "papchenko30_2363")),
        auth: { key_path: File.expand_path("~/.ssh/id_ed25519") }
      )

      sinfo_log = fetcher.call.to_s
      raise sinfo_log if sinfo_log.start_with?("SSH error:")

      result = ActiveRecord::Base.transaction do
        Core::SinfoIngestor.new(
          raw_text: sinfo_log,
          source_cmd: 'sinfo -a',
          parser_version: 'v1',
          quiet: true,
          cluster_id: cluster.id
        ).call
      end

      Rails.cache.write(sinfo_cache_key('result'), result, expires_in: 10.minutes)

      flash[:notice] = "SINFO загружен. Снимок ##{result[:snapshot_id]}, узлов: #{result[:nodes_total]}"

      redirect_to url_for(
        controller: '/core/admin/analytics',
        action: :index,
        cluster_id: cluster.id,
        snapshot_id: result[:snapshot_id]
      )

    rescue => e
      Rails.cache.write(
        sinfo_cache_key('error'),
        "#{e.class}: #{e.message}\n\n#{e.backtrace.take(20).join("\n")}",
        expires_in: 10.minutes
      )

      flash[:alert] = "Ошибка загрузки SINFO: #{e.class}: #{e.message}"

      redirect_to url_for(controller: '/core/admin/analytics', action: :index, cluster_id: cluster_id)
    end

    def create_comment
      if request.get?
        index
        @active_tab = 'comments'
        render :index
        return
      end

      @comment = Core::Comments::Comment.new(comment_params)
      @comment.author = current_user

      new_tag_ids = ensure_custom_tags(custom_tag_labels_from_params)
      @comment.tag_ids = (@comment.tag_ids + new_tag_ids).uniq if new_tag_ids.any?

      if @comment.save
        flash[:notice] = 'Комментарий сохранён.'
        redirect_to url_for(controller: '/core/admin/analytics', action: :create_comment)
      else
        flash.now[:alert] = 'Не удалось сохранить комментарий.'
        index
        @active_tab = 'comments'
        render :index
      end
    end

    def create_tag
      label = params.dig(:tag, :label).to_s.strip
      return render_tags_update(alert: 'Введите название тега.', status: 422) if label.blank?

      group = Core::Comments::TagGroup.find_or_create_by!(key: 'custom') do |g|
        g.name = 'Пользовательские'
        g.sort_order = 1000
        g.is_active = true
      end

      base_key = label.parameterize(separator: '_')
      base_key = "tag_#{SecureRandom.hex(4)}" if base_key.blank?

      key = base_key
      i = 2
      while Core::Comments::Tag.exists?(group_id: group.id, key: key)
        key = "#{base_key}_#{i}"
        i += 1
      end

      tag = Core::Comments::Tag.new(
        group_id: group.id,
        key: key,
        label: label,
        sort_order: 0,
        is_active: true
      )

      if tag.save
        render_tags_update(notice: 'Тег добавлен.', auto_check_tag_id: tag.id)
      else
        render_tags_update(alert: tag.errors.full_messages.to_sentence, status: 422)
      end
    end

    def destroy_tag
      tag = Core::Comments::Tag.find(params[:id])

      if tag.group&.key != 'custom'
        return render_tags_update(alert: 'Удалять можно только пользовательские теги (custom).', status: 422)
      end

      tag.destroy
      render_tags_update(notice: 'Тег удалён.')
    end

    private

    def parse_time(str)
      return nil if str.blank?
      Time.zone.parse(str.to_s)
    rescue StandardError
      nil
    end

    def sinfo_cache_key(suffix)
      "analytics:sinfo:#{suffix}:user:#{current_user&.id || 'anon'}"
    end

    def comment_params
      key =
        if params[:comment].present?
          :comment
        elsif params[:comments_comment].present?
          :comments_comment
        else
          raise ActionController::ParameterMissing, :comment
        end

      permitted = params.require(key).permit(
        :cluster_id,
        :title,
        :body,
        :valid_from,
        :valid_to,
        :severity,
        node_ids: [],
        tag_ids: []
      )

      permitted[:node_ids] = Array(permitted[:node_ids]).reject(&:blank?).map(&:to_i).uniq
      permitted[:tag_ids]  = Array(permitted[:tag_ids]).reject(&:blank?).map(&:to_i).uniq

      permitted
    end

    def role?(name)
      return false unless current_user

      sym  = name.to_sym
      pred = "#{sym}?".to_sym
      if current_user.respond_to?(pred)
        current_user.public_send(pred)
      elsif current_user.respond_to?(:has_role?)
        current_user.has_role?(sym)
      else
        false
      end
    end

    def can_read_reports?
      return false unless respond_to?(:can?)
      can?(:read, :reports) || can?(:manage, :reports)
    rescue StandardError
      false
    end

    def require_analytics_access
      allowed = role?(:superadmin) ||
                role?(:reregistrator) ||
                role?(:admin) ||
                role?(:expert) ||
                can_read_reports?

      redirect_to main_app.admin_users_path, alert: 'Нет доступа к аналитике' unless allowed
    end

    def prepare_comments
      @tag_groups = Core::Comments::TagGroup.includes(:tags).order(:sort_order, :id)
      @tag_usage  = Core::Comments::CommentTag.group(:tag_id).count

      @comment ||= Core::Comments::Comment.new(valid_from: Time.current)

      @nodes = Core::Analytics::Node
               .select(:id, :cluster_id, :hostname, :prefix)
               .order(:cluster_id, :prefix, :hostname)

      rel = Core::Comments::Comment
            .includes(:author, :cluster, :tags, :nodes)
            .recent_first

      rel = rel.where(cluster_id: params[:cluster_id]) if params[:cluster_id].present?
      rel = rel.where(severity: params[:severity]) if params[:severity].present?
      rel = rel.current if params[:active_only].to_s == '1'

      @recent_comments = rel.limit(20)
    end

    def custom_tag_labels_from_params
      raw = params.dig(:comment, :new_tags) || params.dig(:comments_comment, :new_tags)
      return [] if raw.blank?

      raw.to_s
         .split(/[,\n;]/)
         .map(&:strip)
         .reject(&:blank?)
         .uniq
         .take(10)
    end

    def ensure_custom_tags(labels)
      return [] if labels.blank?

      group = Core::Comments::TagGroup.find_or_create_by!(key: 'custom') do |g|
        g.name = 'Пользовательские'
        g.sort_order = 1000
        g.is_active = true
      end

      labels.map { |label| find_or_create_tag_in_group(group, label).id }
    end

    def find_or_create_tag_in_group(group, label)
      existing = Core::Comments::Tag.where(group_id: group.id)
                                   .where('LOWER(label) = ?', label.downcase)
                                   .first
      return existing if existing

      base_key = label.to_s.parameterize(separator: '_')
      base_key = "tag_#{SecureRandom.hex(4)}" if base_key.blank?

      key = base_key
      i = 2
      while Core::Comments::Tag.exists?(group_id: group.id, key: key)
        key = "#{base_key}_#{i}"
        i += 1
      end

      Core::Comments::Tag.create!(
        group_id: group.id,
        key: key,
        label: label,
        sort_order: 0,
        is_active: true
      )
    end

    def load_tags_data
      @tag_groups = Core::Comments::TagGroup.includes(:tags).order(:sort_order, :id)
      @tag_usage  = Core::Comments::CommentTag.group(:tag_id).count
    end

    def render_tags_update(notice: nil, alert: nil, auto_check_tag_id: nil, status: 200)
      load_tags_data

      checkboxes_html = render_to_string(
        partial: 'core/admin/analytics/tags_checkboxes',
        formats: [:html],
        locals: { tag_groups: @tag_groups, comment: @comment || Core::Comments::Comment.new }
      )

      manage_html = render_to_string(
        partial: 'core/admin/analytics/tags_manage',
        formats: [:html],
        locals: { tag_groups: @tag_groups, tag_usage: @tag_usage }
      )

      js = <<~JS
        (function(){
          var checked = Array.prototype.slice.call(
            document.querySelectorAll('#tag_checkboxes_container input[type="checkbox"]:checked')
          ).map(function(cb){ return cb.value; });

          var c = document.getElementById('tag_checkboxes_container');
          var m = document.getElementById('tag_manage_container');

          if (c) { c.innerHTML = #{checkboxes_html.to_json}; }
          if (m) { m.innerHTML = #{manage_html.to_json}; }

          checked.forEach(function(id){
            var cb = document.querySelector('#tag_checkboxes_container input[type="checkbox"][value="'+id+'"]');
            if (cb) cb.checked = true;
          });

          #{auto_check_tag_id ? "var cb2=document.querySelector('#tag_checkboxes_container input[type=\"checkbox\"][value=\"#{auto_check_tag_id}\"]'); if(cb2) cb2.checked=true;" : ""}

          var n=document.getElementById('tags_notice');
          if(n){
            n.textContent = #{(notice || '').to_json};
            n.style.display = #{notice ? "'block'" : "'none'"};
          }
          var a=document.getElementById('tags_alert');
          if(a){
            a.textContent = #{(alert || '').to_json};
            a.style.display = #{alert ? "'block'" : "'none'"};
          }
        })();
      JS

      render js: js, status: status
    end
  end
end
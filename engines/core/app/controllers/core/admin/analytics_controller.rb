module Core
  class Admin::AnalyticsController < Admin::ApplicationController
    skip_before_action :authorize_admins, only: [:index, :sinfo, :create_comment], raise: false
    before_action :require_analytics_access
    octo_use(:project_class, :core, 'Project')

    before_action :prepare_comments, only: [:index]

    def index
      @total_reports     = 0
      @submitted_reports = 0
      @assessing_reports = 0
      @rejected_reports  = 0

      @systems = Core::Analytics::System.order(:name).includes(:nodes)

      node_states_rel = Core::Analytics::NodeState.current

      @global_state_counts = node_states_rel.group(:state).count

      @system_stats = {}
      @systems.each do |system|
        @system_stats[system.id] = {
          total_nodes: system.nodes.size,
          states:      Hash.new(0),
          issues:      0
        }
      end

      states_counts = node_states_rel.group(:system_id, :state).count
      states_counts.each do |(system_id, state), count|
        next unless @system_stats.key?(system_id)
        @system_stats[system_id][:states][state] = count
      end

      issues_counts = node_states_rel.where(has_reason: true).group(:system_id).count
      issues_counts.each do |system_id, count|
        next unless @system_stats.key?(system_id)
        @system_stats[system_id][:issues] = count
      end

      @partition_stats = {}

      partition_counts = node_states_rel.joins(:partition)
                                        .group(
                                          'core_analytics_partitions.system_id',
                                          'core_analytics_partitions.id',
                                          'core_analytics_partitions.name',
                                          'core_analytics_node_states.state'
                                        ).count

      partition_counts.each do |(system_id, partition_id, partition_name, state), count|
        @partition_stats[system_id] ||= {}
        @partition_stats[system_id][partition_id] ||= {
          name:   partition_name,
          states: Hash.new(0)
        }
        @partition_stats[system_id][partition_id][:states][state] = count
      end

      @latest_snapshots = Core::Analytics::Snapshot.latest_first.includes(:system).limit(10)
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

      @comment ||= Core::Comments::Comment.new
      @recent_comments = Core::Comments::Comment.order(valid_from: :desc, created_at: :desc)
                                                

      @active_tab ||= 'analytics'
    end


    def sinfo
      fetcher = Core::SinfoFetcher.new(
        host: ENV.fetch("HPC_HOST", "188.44.52.12"),
        user: ENV.fetch("HPC_USER", "papchenko30_2363"),
        auth: { forward_agent: true }
      )
      @sinfo_log = fetcher.call.to_s

      result = ActiveRecord::Base.transaction do
        Core::SinfoIngestor.new(
          raw_text: @sinfo_log,
          source_cmd: 'sinfo -a',
          parser_version: 'v1',
          quiet: true
        ).call
      end

      respond_to do |format|
        format.js do
          js = <<~JS
            var panel = document.getElementById('sinfo_log_panel');
            var pre   = document.getElementById('sinfo_log');
            var res   = document.getElementById('sinfo_result');

            if (panel) { panel.style.display = 'block'; }
            if (pre)   { pre.textContent = #{(@sinfo_log.presence || "(пустой вывод)").to_json}; }
            if (res)   { res.textContent = #{result.to_json}; }
          JS
          render js: js
        end
        format.html do
          flash.now[:notice] = "SINFO загружен. Снимок ##{result[:snapshot_id]}, узлов: #{result[:nodes_total]}, строк: #{result[:rows_written]}, партиций: #{result[:partitions]}"
          index
          render :index
        end
        format.any { render json: { ok: true, result: result, sinfo: @sinfo_log }, status: 200 }
      end
    rescue => e
      Rails.logger.error("[analytics#sinfo] #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
      respond_to do |format|
        format.js   { render js: "alert('Ошибка загрузки SINFO: #{e.message}');", status: 500 }
        format.html { redirect_to action: :index, alert: "Ошибка: #{e.message}" }
        format.any  { render json: { ok: false, error: e.message }, status: 500 }
      end
    end

    def create_comment
      if request.get?
        index
        @active_tab = 'comments'
        render :index
      else
        @comment = Core::Comments::Comment.new(comment_params)

        comments_user = Core::Comments::User.find_or_initialize_by(email: current_user.email)

        if comments_user.new_record?
          comments_user.name =
            current_user.try(:full_name) ||
            current_user.try(:name) ||
            current_user.email

          comments_user.save!
        end

        @comment.author = comments_user

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
    end


    private


    def comment_params
      key =
        if params[:comment].present?
          :comment
        elsif params[:comments_comment].present?
          :comments_comment
        else
          raise ActionController::ParameterMissing, :comment
        end

      params.require(key).permit(
        :title,
        :body,
        :valid_from,
        :valid_to,
        :severity,
        :pinned,
        :system_id,
        tag_keys: []
      )
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
      begin
        can?(:read, :reports) || can?(:manage, :reports)
      rescue StandardError
        false
      end
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
      @comment = Core::Comments::Comment.new(valid_from: Time.current)
      @recent_comments = Core::Comments::Comment
                           .includes(:author)
                           .recent_first
                           .limit(20)
    end

  end
end

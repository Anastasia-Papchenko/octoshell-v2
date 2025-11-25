# module Core
#   class Admin::AnalyticsController < Admin::ApplicationController
#     skip_before_action :authorize_admins, only: [:index, :sinfo], raise: false
#     before_action :require_analytics_access
#     octo_use(:project_class, :core, 'Project')

#     def index
#       @total_reports     = 0
#       @submitted_reports = 0
#       @assessing_reports = 0
#       @rejected_reports  = 0

#     end

#     def sinfo
#       fetcher = Core::SinfoFetcher.new(
#         host: ENV.fetch("HPC_HOST", "188.44.52.12"),
#         user: ENV.fetch("HPC_USER", "papchenko30_2363"),
#         auth: { forward_agent: true }
#       )
#       @sinfo_log = fetcher.call.to_s

#       result = ActiveRecord::Base.transaction do
#         Core::SinfoIngestor.new(
#           raw_text: @sinfo_log,
#           source_cmd: 'sinfo -a',
#           parser_version: 'v1',
#           quiet: true
#         ).call
#       end

#       respond_to do |format|
#         format.js do
#           js = <<~JS
#             var panel = document.getElementById('sinfo_log_panel');
#             var pre   = document.getElementById('sinfo_log');
#             var res   = document.getElementById('sinfo_result');

#             if (panel) { panel.style.display = 'block'; }
#             if (pre)   { pre.textContent = #{(@sinfo_log.presence || "(пустой вывод)").to_json}; }
#             if (res)   { res.textContent = #{result.to_json}; }
#           JS
#           render js: js
#         end
#         format.html do
#           flash.now[:notice] = "SINFO загружен. Снимок ##{result[:snapshot_id]}, узлов: #{result[:nodes_total]}, строк: #{result[:rows_written]}, партиций: #{result[:partitions]}"
#           index
#           render :index
#         end
#         format.any { render json: { ok: true, result: result, sinfo: @sinfo_log }, status: 200 }
#       end
#     rescue => e
#       Rails.logger.error("[analytics#sinfo] #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
#       respond_to do |format|
#         format.js   { render js: "alert('Ошибка загрузки SINFO: #{e.message}');", status: 500 }
#         format.html { redirect_to action: :index, alert: "Ошибка: #{e.message}" }
#         format.any  { render json: { ok: false, error: e.message }, status: 500 }
#       end
#     end

#     private

#     def role?(name)
#       return false unless current_user

#       sym  = name.to_sym
#       pred = "#{sym}?".to_sym
#       if current_user.respond_to?(pred)
#         current_user.public_send(pred)
#       elsif current_user.respond_to?(:has_role?)
#         current_user.has_role?(sym)
#       else
#         false
#       end
#     end

#     def can_read_reports?
#       return false unless respond_to?(:can?)
#       begin
#         can?(:read, :reports) || can?(:manage, :reports)
#       rescue StandardError
#         false
#       end
#     end

#     def require_analytics_access
#       allowed = role?(:superadmin) ||
#                 role?(:reregistrator) ||
#                 role?(:admin) ||
#                 role?(:expert) ||
#                 can_read_reports?

#       redirect_to main_app.admin_users_path, alert: 'Нет доступа к аналитике' unless allowed
#     end
#   end
# end





module Core
  class Admin::AnalyticsController < Admin::ApplicationController
    skip_before_action :authorize_admins, only: [:index, :sinfo], raise: false
    before_action :require_analytics_access
    octo_use(:project_class, :core, 'Project')

    def index
      @total_reports     = 0
      @submitted_reports = 0
      @assessing_reports = 0
      @rejected_reports  = 0

      @systems = Core::Analytics::System.order(:name).includes(:nodes)

      node_states_rel = Core::Analytics::NodeState.current

      # --- Глобальная статистика по состояниям (для круговой диаграммы) ---
      @global_state_counts = node_states_rel.group(:state).count
      # например: { "alloc" => 120, "idle" => 30, "down" => 5, ... }

      # ---- Статистика по системам ----
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

      # ---- Статистика по партициям ----
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

      # ---- История: последние снапшоты ----
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

    private

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
  end
end

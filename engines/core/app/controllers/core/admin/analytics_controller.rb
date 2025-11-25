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

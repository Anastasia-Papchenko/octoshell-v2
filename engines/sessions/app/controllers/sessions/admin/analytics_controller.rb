module Sessions
  class Admin::AnalyticsController < Admin::ApplicationController

    skip_before_action :authorize_admins, only: [:index, :sinfo], raise: false
    before_action :require_analytics_access

    octo_use(:project_class, :core, 'Project')

    def index
      @search = Report.includes([{ author: :profile }, { expert: :profile }, :session])
                      .for_link(:project) { |r| r.includes(project: :research_areas) }
                      .search(params[:q] || {})

      if role?(:superadmin) || role?(:reregistrator) || role?(:admin) || can_read_reports?
        @reports = @search.result(distinct: true)
      elsif role?(:expert)
        @reports = @search.result(distinct: true).where(expert_id: [nil, current_user.id])
      else
        @reports = Report.none
      end

      @total_reports     = @reports.count
      @submitted_reports = @reports.where(state: 'submitted').count
      @assessing_reports = @reports.where(state: 'assessing').count
      @rejected_reports  = @reports.where(state: 'rejected').count

      without_pagination :reports
    end

    def sinfo
      fetcher = Sessions::SinfoFetcher.new(
        host: ENV.fetch("HPC_HOST", "188.44.52.12"),
        user: ENV.fetch("HPC_USER", "papchenko30_2363"),
        auth: { forward_agent: true }
      )

      @sinfo_log = fetcher.call

      respond_to do |format|
        format.js do
          js = <<~JS
            var panel = document.getElementById('sinfo_log_panel');
            var pre   = document.getElementById('sinfo_log');
            if (panel) { panel.style.display = 'block'; }
            if (pre)   { pre.textContent = #{(@sinfo_log || "(пустой вывод)").to_json}; }
          JS
          render js: js
        end
        format.html do
          index
          render :index
        end
        format.any { render plain: @sinfo_log.to_s, status: 200 }
      end
    # rescue => e
    #   Rails.logger.error("[analytics#sinfo] #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
    #   render plain: "analytics#sinfo FAILED: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}", status: 500
    end


    private

    def role?(name)
      return false unless current_user

      sym = name.to_sym
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
      allowed = role?(:superadmin) || role?(:reregistrator) || role?(:admin) || role?(:expert) || can_read_reports?
      redirect_to main_app.admin_users_path, alert: 'Нет доступа к аналитике' unless allowed
    end
  end
end

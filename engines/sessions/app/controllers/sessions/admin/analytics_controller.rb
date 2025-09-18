module Sessions
  class Admin::AnalyticsController < Admin::ApplicationController
    # before_action :octo_authorize!   # ← убираем, он ломается на новом пути
    before_action -> { authorize! :manage, :reports }  # или :read, :reports — как у вас принято

    octo_use(:project_class, :core, 'Project')

    def index
      # тот же набор includes, что и в Reports#index — чтобы таблица работала так же быстро
      @search = Report.includes([{ author: :profile }, { expert: :profile }, :session])
                      .for_link(:project) { |r| r.includes(project: :research_areas) }
                      .search(params[:q] || {})

      # та же ролевая фильтрация, что в ReportsController#index
      @reports =
        if (User.superadmins | User.reregistrators).include?(current_user)
          @search.result(distinct: true)
        elsif User.experts.include?(current_user)
          @search.result(distinct: true).where(expert_id: [nil, current_user.id])
        else
          Report.none
        end

      # базовые KPI (по желанию)
      @total_reports     = @reports.count
      @submitted_reports = @reports.where(state: 'submitted').count
      @assessing_reports = @reports.where(state: 'assessing').count
      @rejected_reports  = @reports.where(state: 'rejected').count

      # чтобы в аналитике тоже работала пагинация как у тебя (или убери эту строку, если не нужно)
      without_pagination :reports
    end
  end
end

module Sessions
  module Admin
    class Sessions::Admin::AnalyticsController < ApplicationController
      layout "layouts/sessions/admin" # или свой layout, если используется другой

      def index
        @message = "Аналитика загружена успешно!"
      end
    end
  end
end

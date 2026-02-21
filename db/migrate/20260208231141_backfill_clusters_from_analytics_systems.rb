class BackfillClustersFromAnalyticsSystems < ActiveRecord::Migration[5.2]
  class AnalyticsSystem < ActiveRecord::Base
    self.table_name = 'core_analytics_systems'
  end

  class Cluster < ActiveRecord::Base
    self.table_name = 'core_clusters'
  end

  def up
    AnalyticsSystem.find_each do |s|
      Cluster.find_or_create_by!(analytics_system_id: s.id) do |c|
        c.name_ru = s.name
        c.name_en = s.name
        c.host = s.slug
        c.admin_login = 'root'         
        c.available_for_work = true
      end
    end
  end

  def down
  end
end

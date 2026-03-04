class AddAnalyticsSystemIdToCoreClusters < ActiveRecord::Migration[5.2]
  def change
    add_column :core_clusters, :analytics_system_id, :bigint
    add_index  :core_clusters, :analytics_system_id, unique: true
  end
end

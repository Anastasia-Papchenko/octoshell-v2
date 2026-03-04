class RepointSystemForeignKeysToClusters < ActiveRecord::Migration[5.2]
  def up
    remove_foreign_key :core_analytics_nodes,       column: :system_id
    remove_foreign_key :core_analytics_partitions,  column: :system_id
    remove_foreign_key :core_analytics_snapshots,   column: :system_id
    remove_foreign_key :core_analytics_node_states, column: :system_id

    begin
      remove_foreign_key :core_comments, column: :system_id
    rescue StandardError
    end

    add_foreign_key :core_analytics_nodes, :core_clusters,
                    column: :system_id, primary_key: :analytics_system_id

    add_foreign_key :core_analytics_partitions, :core_clusters,
                    column: :system_id, primary_key: :analytics_system_id

    add_foreign_key :core_analytics_snapshots, :core_clusters,
                    column: :system_id, primary_key: :analytics_system_id

    add_foreign_key :core_analytics_node_states, :core_clusters,
                    column: :system_id, primary_key: :analytics_system_id

    add_foreign_key :core_comments, :core_clusters,
                    column: :system_id, primary_key: :analytics_system_id
  end

  def down
    remove_foreign_key :core_analytics_nodes,       column: :system_id
    remove_foreign_key :core_analytics_partitions,  column: :system_id
    remove_foreign_key :core_analytics_snapshots,   column: :system_id
    remove_foreign_key :core_analytics_node_states, column: :system_id
    remove_foreign_key :core_comments,              column: :system_id

    add_foreign_key :core_analytics_nodes, :core_analytics_systems, column: :system_id
    add_foreign_key :core_analytics_partitions, :core_analytics_systems, column: :system_id
    add_foreign_key :core_analytics_snapshots, :core_analytics_systems, column: :system_id
    add_foreign_key :core_analytics_node_states, :core_analytics_systems, column: :system_id
  end
end

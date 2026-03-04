class RebuildCoreAnalyticsToUseClustersAndCorePartitions < ActiveRecord::Migration[5.2]
  def change
    drop_table :core_analytics_node_states, if_exists: true
    drop_table :core_analytics_snapshots,   if_exists: true
    remove_foreign_key :core_comments_nodes, :core_analytics_nodes
    drop_table :core_analytics_nodes,       if_exists: true
    drop_table :core_analytics_partitions,  if_exists: true
    drop_table :core_analytics_systems,     if_exists: true


    create_table :core_analytics_nodes do |t|
      t.references :cluster, null: false, foreign_key: { to_table: :core_clusters }, index: true
      t.string :hostname, null: false
      t.string :prefix, null: false
      t.timestamps null: false
    end
    add_index :core_analytics_nodes, [:cluster_id, :hostname], unique: true,
              name: 'index_core_analytics_nodes_on_cluster_id_and_hostname'

    create_table :core_analytics_snapshots do |t|
      t.references :cluster, null: false, foreign_key: { to_table: :core_clusters }, index: true
      t.datetime :captured_at, null: false
      t.string   :source_cmd, null: false
      t.string   :parser_version, null: false
      t.text     :raw_text, null: false
      t.timestamps null: false
    end
    add_index :core_analytics_snapshots, [:cluster_id, :captured_at],
              name: 'index_core_analytics_snapshots_on_cluster_id_and_captured_at'

    create_table :core_analytics_node_states do |t|
      t.references :cluster,   null: false, foreign_key: { to_table: :core_clusters }, index: true
      t.references :snapshot,  null: false, foreign_key: { to_table: :core_analytics_snapshots }, index: true
      t.references :node,      null: false, foreign_key: { to_table: :core_analytics_nodes }, index: true

      t.references :partition, null: false, foreign_key: { to_table: :core_partitions }, index: true

      t.string  :state, null: false
      t.string  :substate
      t.boolean :has_reason, null: false, default: false
      t.datetime :valid_from, null: false
      t.datetime :valid_to
      t.timestamps null: false
    end

    add_index :core_analytics_node_states, [:snapshot_id, :node_id],
              unique: true, name: 'core_analytics_uniq_node_state_per_snapshot'
    add_index :core_analytics_node_states, [:node_id, :valid_from],
              name: 'core_analytics_index_node_states_on_node_id_and_valid_from'
    add_index :core_analytics_node_states, [:node_id, :valid_to],
              name: 'core_analytics_index_node_states_on_node_id_and_valid_to'
    add_index :core_analytics_node_states, :node_id,
              where: 'valid_to IS NULL',
              name: 'core_analytics_index_node_states_current_on_node_id'

    add_index :core_partitions, [:cluster_id, :name], unique: true
  end
end

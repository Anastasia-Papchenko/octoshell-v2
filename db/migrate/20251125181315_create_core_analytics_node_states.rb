class CreateCoreAnalyticsNodeStates < ActiveRecord::Migration[5.2]
  def change
    create_table :core_analytics_node_states do |t|
      t.references :system,    null: false, index: true
      t.references :snapshot,  null: false, index: true
      t.references :node,      null: false, index: true
      t.references :partition, null: false, index: true

      t.string  :state,      null: false
      t.string  :substate
      t.boolean :has_reason, null: false, default: false

      t.datetime :valid_from, null: false
      t.datetime :valid_to

      t.timestamps
    end

    add_index :core_analytics_node_states, [:snapshot_id, :node_id],
              unique: true,
              name: 'core_analytics_uniq_node_state_per_snapshot'

    add_index :core_analytics_node_states, [:node_id, :valid_from],
              name: 'core_analytics_index_node_states_on_node_id_and_valid_from'
    add_index :core_analytics_node_states, [:node_id, :valid_to],
              name: 'core_analytics_index_node_states_on_node_id_and_valid_to'

    add_index :core_analytics_node_states, :node_id,
              where: 'valid_to IS NULL',
              name: 'core_analytics_index_node_states_current_on_node_id'

    add_foreign_key :core_analytics_node_states,
                    :core_analytics_systems,
                    column: :system_id

    add_foreign_key :core_analytics_node_states,
                    :core_analytics_snapshots,
                    column: :snapshot_id

    add_foreign_key :core_analytics_node_states,
                    :core_analytics_nodes,
                    column: :node_id

    add_foreign_key :core_analytics_node_states,
                    :core_analytics_partitions,
                    column: :partition_id
  end
end

class CreateCoreAnalyticsNodes < ActiveRecord::Migration[5.2]
  def change
    create_table :core_analytics_nodes do |t|
      t.references :system, null: false, index: true
      t.string :hostname, null: false
      t.string :prefix,   null: false
      t.timestamps
    end

    add_index :core_analytics_nodes, [:system_id, :hostname],
              unique: true,
              name: 'index_core_analytics_nodes_on_system_id_and_hostname'

    add_foreign_key :core_analytics_nodes,
                    :core_analytics_systems,
                    column: :system_id
  end
end

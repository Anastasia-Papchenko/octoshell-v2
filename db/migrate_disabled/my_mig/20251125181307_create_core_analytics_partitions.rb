class CreateCoreAnalyticsPartitions < ActiveRecord::Migration[5.2]
  def change
    create_table :core_analytics_partitions do |t|
      t.references :system, null: false, index: true
      t.string :name, null: false
      t.string :time_limit
      t.timestamps
    end

    add_index :core_analytics_partitions, [:system_id, :name],
              unique: true,
              name: 'index_core_analytics_partitions_on_system_id_and_name'

    add_foreign_key :core_analytics_partitions,
                    :core_analytics_systems,
                    column: :system_id
  end
end

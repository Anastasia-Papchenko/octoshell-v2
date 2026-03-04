class CreateCoreAnalyticsSnapshots < ActiveRecord::Migration[5.2]
  def change
    create_table :core_analytics_snapshots do |t|
      t.references :system, null: false, index: true
      t.datetime :captured_at,    null: false
      t.string   :source_cmd,     null: false
      t.string   :parser_version, null: false
      t.text     :raw_text,       null: false
      t.timestamps
    end

    add_index :core_analytics_snapshots, [:system_id, :captured_at],
              name: 'index_core_analytics_snapshots_on_system_id_and_captured_at'

    add_foreign_key :core_analytics_snapshots,
                    :core_analytics_systems,
                    column: :system_id
  end
end

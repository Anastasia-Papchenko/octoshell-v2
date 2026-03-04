class CreateCoreAnalyticsSystems < ActiveRecord::Migration[5.2]
  def change
    create_table :core_analytics_systems do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :timezone
      t.string :sinfo_cmd
      t.timestamps
    end

    add_index :core_analytics_systems, :name, unique: true
    add_index :core_analytics_systems, :slug, unique: true
  end
end

class CreateCoreCommentsComments < ActiveRecord::Migration[5.2]
  def change
    create_table :core_comments do |t|
      t.references :author, null: false, type: :integer, foreign_key: { to_table: :users }  
      t.references :system, null: false, index: true      # -> core_analytics_systems

      t.string   :title, null: false
      t.text     :body
      t.datetime :valid_from, null: false
      t.datetime :valid_to
      t.integer  :severity, null: false, default: 0

      t.timestamps null: false
    end

    add_index :core_comments, [:cluster_id, :valid_from],
              name: 'index_core_comments_on_system_id_and_valid_from'
    add_index :core_comments, [:cluster_id, :valid_to],
              name: 'index_core_comments_on_system_id_and_valid_to'
    add_index :core_comments, [:cluster_id :severity],
              name: 'index_core_comments_on_system_id_and_severity'

    add_index :core_comments, :cluster_id,
              where: 'valid_to IS NULL',
              name: 'index_core_comments_current_open_ended_on_system_id'
  end
end

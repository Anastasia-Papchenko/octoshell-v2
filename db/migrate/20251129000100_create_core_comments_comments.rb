class CreateCoreComments < ActiveRecord::Migration[5.2]
  def change
    create_table :core_comments do |t|
      t.bigint :author_id, null: false       
      t.bigint :system_id                      

      t.string :title, null: false               
      t.text   :body                             

      t.datetime :valid_from, null: false      
      t.datetime :valid_to

      t.integer :severity, null: false, default: 0 
      t.boolean :pinned,   null: false, default: false

      t.string :tag_keys, array: true, null: false, default: []

      t.timestamps null: false
    end

    add_index :core_comments, :author_id
    add_index :core_comments, :system_id
    add_index :core_comments, :valid_from
    add_index :core_comments, :valid_to
    add_index :core_comments, :tag_keys, using: :gin

    add_foreign_key :core_comments, :users, column: :author_id
  end
end

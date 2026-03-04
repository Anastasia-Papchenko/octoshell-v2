class CreateCoreCommentsTags < ActiveRecord::Migration[5.2]
  def change
    create_table :core_tags do |t|
      t.references :group, null: false, index: true     

      t.string  :key,        null: false
      t.string  :label,      null: false
      t.integer :sort_order, null: false, default: 0
      t.boolean :is_active,  null: false, default: true

      t.timestamps null: false
    end

    add_index :core_tags, [:group_id, :key],
              unique: true,
              name: 'index_core_tags_unique_group_key'

    add_index :core_tags, [:group_id, :is_active, :sort_order],
              name: 'index_core_tags_on_group_active_sort'

    add_foreign_key :core_tags,
                    :core_tag_groups,
                    column: :group_id
  end
end

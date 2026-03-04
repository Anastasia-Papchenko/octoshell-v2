class CreateCoreCommentsCommentTags < ActiveRecord::Migration[5.2]
  def change
    create_table :core_comment_tags, id: false do |t|
      t.references :comment, null: false, index: false
      t.references :tag,     null: false, index: false

      t.datetime :created_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
    end

    add_index :core_comment_tags, [:comment_id, :tag_id],
              unique: true,
              name: 'index_core_comment_tags_unique_comment_tag'

    add_index :core_comment_tags, :tag_id,
              name: 'index_core_comment_tags_on_tag_id'

    add_foreign_key :core_comment_tags,
                    :core_comments,
                    column: :comment_id

    add_foreign_key :core_comment_tags,
                    :core_tags,
                    column: :tag_id
  end
end

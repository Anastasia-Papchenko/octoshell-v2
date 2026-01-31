class CreateCoreCommentsCommentsNodes < ActiveRecord::Migration[5.2]
  def change
    create_table :core_comments_nodes do |t|
      t.references :comment, null: false, index: true
      t.references :node,    null: false, index: true

      t.timestamps null: false
    end

    add_index :core_comments_nodes, [:comment_id, :node_id],
              unique: true,
              name: 'index_core_comments_nodes_unique_comment_node'

    # add_index :core_comments_nodes, :node_id,
    #           name: 'index_core_comments_nodes_on_node_id'

    add_foreign_key :core_comments_nodes,
                    :core_comments,
                    column: :comment_id

    add_foreign_key :core_comments_nodes,
                    :core_analytics_nodes,
                    column: :node_id
  end
end

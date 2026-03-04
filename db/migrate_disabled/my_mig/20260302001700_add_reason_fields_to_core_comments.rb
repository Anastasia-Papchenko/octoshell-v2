class AddReasonFieldsToCoreComments < ActiveRecord::Migration[8.0]
  def change
    add_column :core_comments, :reason_group_id, :integer
    add_column :core_comments, :reason_id, :integer

    add_index :core_comments, :reason_group_id
    add_index :core_comments, :reason_id
    add_index :core_comments, [:reason_group_id, :reason_id]
  end
end
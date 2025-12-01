class CreateCoreUsers < ActiveRecord::Migration[5.2]
  def change
    create_table :core_comments_users do |t|
      t.string :email, null: false
      t.string :name

      t.timestamps null: false
    end

    add_index :core_comments_users, :email, unique: true
  end
end

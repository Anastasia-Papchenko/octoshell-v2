class CreateSessionsSlurmNodes < ActiveRecord::Migration[5.2]
  def change
    create_table :sessions_slurm_nodes do |t|
      t.text    :hostname, null: false
      t.text    :prefix,   null: false
      t.integer :number

      t.timestamps
    end

    add_index :sessions_slurm_nodes, :hostname, unique: true
    add_index :sessions_slurm_nodes, [:prefix, :number], name: "idx_sessions_slurm_nodes_prefix_number"
  end
end

class CreateHardwareSlurmNodes < ActiveRecord::Migration[5.2]
  def change
    create_table :hardware_slurm_nodes do |t|
      t.string  :hostname, null: false
      t.string  :prefix,   null: false
      t.integer :number
      t.timestamps
    end
    add_index :hardware_slurm_nodes, :hostname, unique: true
    add_index :hardware_slurm_nodes, [:prefix, :number]
  end
end

class CreateHardwareSlurmNodes < ActiveRecord::Migration[5.2]
  def change
    create_table :hardware_slurm_nodes do |t|
      t.references :system, null: false, index: true
      t.string :hostname, null: false
      t.string :prefix,   null: false
      t.timestamps
    end

    add_index :hardware_slurm_nodes, [:system_id, :hostname],
              unique: true, name: 'index_slurm_nodes_on_system_id_and_hostname'

    add_foreign_key :hardware_slurm_nodes, :hardware_slurm_systems, column: :system_id
  end
end

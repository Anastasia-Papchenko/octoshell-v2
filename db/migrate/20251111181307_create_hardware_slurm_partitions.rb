class CreateHardwareSlurmPartitions < ActiveRecord::Migration[5.2]
  def change
    create_table :hardware_slurm_partitions do |t|
      t.references :system, null: false, index: true
      t.string :name, null: false
      t.string :time_limit   
      t.timestamps
    end

    add_index :hardware_slurm_partitions, [:system_id, :name],
              unique: true, name: 'index_slurm_partitions_on_system_id_and_name'

    add_foreign_key :hardware_slurm_partitions, :hardware_slurm_systems, column: :system_id
  end
end

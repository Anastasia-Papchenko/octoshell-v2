# This migration comes from hardware (originally 20251102090100)
class CreateHardwareSlurmPartitions < ActiveRecord::Migration[5.2]
  def change
    create_table :hardware_slurm_partitions do |t|
      t.string :name, null: false
      t.string :time_limit
      t.timestamps
    end
    add_index :hardware_slurm_partitions, :name, unique: true
  end
end

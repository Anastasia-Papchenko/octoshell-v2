class CreateSessionsSlurmPartitions < ActiveRecord::Migration[5.2]
  def change
    create_table :sessions_slurm_partitions do |t|
      t.text :name, null: false
      t.text :time_limit

      t.timestamps
    end

    add_index :sessions_slurm_partitions, :name, unique: true
  end
end

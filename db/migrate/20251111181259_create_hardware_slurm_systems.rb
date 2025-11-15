class CreateHardwareSlurmSystems < ActiveRecord::Migration[5.2]
  def change
    create_table :hardware_slurm_systems do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :timezone
      t.string :sinfo_cmd
      t.timestamps
    end

    add_index :hardware_slurm_systems, :name, unique: true
    add_index :hardware_slurm_systems, :slug, unique: true
  end
end

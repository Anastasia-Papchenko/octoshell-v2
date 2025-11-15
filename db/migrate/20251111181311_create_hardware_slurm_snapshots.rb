class CreateHardwareSlurmSnapshots < ActiveRecord::Migration[5.2]
  def change
    create_table :hardware_slurm_snapshots do |t|
      t.references :system, null: false, index: true
      t.datetime :captured_at,    null: false
      t.string   :source_cmd,     null: false
      t.string   :parser_version, null: false
      t.text     :raw_text,       null: false
      t.timestamps
    end

    add_index :hardware_slurm_snapshots, [:system_id, :captured_at],
              name: 'index_slurm_snapshots_on_system_id_and_captured_at'

    add_foreign_key :hardware_slurm_snapshots, :hardware_slurm_systems, column: :system_id
  end
end

# This migration comes from hardware (originally 20251102090200)
class CreateHardwareSlurmSnapshots < ActiveRecord::Migration[5.2]
  def change
    create_table :hardware_slurm_snapshots do |t|
      t.datetime :captured_at,    null: false
      t.string   :source_cmd,     null: false, default: 'sinfo -a'
      t.string   :parser_version, null: false, default: 'v1'
      t.text     :raw_text,       null: false
      t.timestamps
    end
    add_index :hardware_slurm_snapshots, :captured_at
  end
end

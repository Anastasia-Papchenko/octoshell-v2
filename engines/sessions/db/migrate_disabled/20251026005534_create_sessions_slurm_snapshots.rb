class CreateSessionsSlurmSnapshots < ActiveRecord::Migration[5.2]
  def change
    create_table :sessions_slurm_snapshots do |t|
      t.datetime :captured_at,    null: false, default: -> { "NOW()" }
      t.text     :source_cmd,     null: false, default: 'sinfo -a'
      t.text     :raw_text,       null: false
      t.text     :parser_version, null: false, default: 'v1'

      t.timestamps
    end

    add_index :sessions_slurm_snapshots, :captured_at
  end
end

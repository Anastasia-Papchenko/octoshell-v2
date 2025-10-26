class CreateSessionsSlurmNodeSnapshots < ActiveRecord::Migration[5.2]
  def change
    create_table :sessions_slurm_node_snapshots do |t|
      t.references :snapshot,   null: false, foreign_key: { to_table: :sessions_slurm_snapshots }
      t.references :node,       null: false, foreign_key: { to_table: :sessions_slurm_nodes }
      t.references :partition,  null: false, foreign_key: { to_table: :sessions_slurm_partitions }

      t.string  :state,      null: false
      t.boolean :has_reason, null: false, default: false

      t.timestamps
    end

    add_index :sessions_slurm_node_snapshots,
              [:snapshot_id, :node_id],
              unique: true,
              name: "idx_sessions_node_snapshots_unique_snapshot_node"

    add_index :sessions_slurm_node_snapshots,
              [:partition_id, :state],
              name: "idx_sessions_node_snapshots_partition_state"
  end
end

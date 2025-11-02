# This migration comes from hardware (originally 20251102090400)
class CreateHardwareSlurmNodeSnapshots < ActiveRecord::Migration[5.2]
  def change
    create_table :hardware_slurm_node_snapshots do |t|
      t.references :slurm_snapshot,  null: false, foreign_key: { to_table: :hardware_slurm_snapshots }
      t.references :slurm_node,      null: false, foreign_key: { to_table: :hardware_slurm_nodes }
      t.references :slurm_partition, null: false, foreign_key: { to_table: :hardware_slurm_partitions }

      t.string  :state,      null: false   # без DB-enum, валидации на уровне модели
      t.string  :substate
      t.boolean :has_reason, null: false, default: false
      t.timestamps
    end

    add_index :hardware_slurm_node_snapshots,
              [:slurm_snapshot_id, :slurm_node_id],
              unique: true, name: 'idx_hsns_snapshot_node'

    add_index :hardware_slurm_node_snapshots,
              [:slurm_partition_id, :state],
              name: 'idx_hsns_partition_state'
  end
end

class CreateHardwareSlurmNodeStates < ActiveRecord::Migration[5.2]
  def change
    create_table :hardware_slurm_node_states do |t|
      t.references :system,          null: false, index: true
      t.references :slurm_snapshot,  null: false, index: true
      t.references :slurm_node,      null: false, index: true
      t.references :slurm_partition, null: false, index: true

      t.string  :state,      null: false
      t.string  :substate
      t.boolean :has_reason, null: false, default: false

      t.datetime :valid_from, null: false
      t.datetime :valid_to

      t.timestamps
    end

    add_index :hardware_slurm_node_states, [:slurm_snapshot_id, :slurm_node_id],
              unique: true, name: 'uniq_node_state_per_snapshot'

    add_index :hardware_slurm_node_states, [:slurm_node_id, :valid_from],
              name: 'index_node_states_on_node_id_and_valid_from'
    add_index :hardware_slurm_node_states, [:slurm_node_id, :valid_to],
              name: 'index_node_states_on_node_id_and_valid_to'
    add_index :hardware_slurm_node_states, :slurm_node_id,
              where: 'valid_to IS NULL',
              name: 'index_node_states_current_on_node_id'

    add_foreign_key :hardware_slurm_node_states, :hardware_slurm_systems,    column: :system_id
    add_foreign_key :hardware_slurm_node_states, :hardware_slurm_snapshots,  column: :slurm_snapshot_id
    add_foreign_key :hardware_slurm_node_states, :hardware_slurm_nodes,      column: :slurm_node_id
    add_foreign_key :hardware_slurm_node_states, :hardware_slurm_partitions, column: :slurm_partition_id
  end
end

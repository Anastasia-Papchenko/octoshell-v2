class CreateOctoSlurmSchema < ActiveRecord::Migration[5.2]
  def up
    execute %(CREATE SCHEMA IF NOT EXISTS "octo";)

    execute <<~SQL
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_type t
          JOIN pg_namespace n ON n.oid = t.typnamespace
          WHERE t.typname = 'slurm_node_state' AND n.nspname = 'octo'
        ) THEN
          CREATE TYPE "octo".slurm_node_state AS ENUM
            ('alloc','idle','comp','drain','drng','down','maint','reserved','mix');
        END IF;
      END;
      $$;
    SQL

    create_table :"octo.slurm_partitions" do |t|
      t.text :name, null: false
      t.text :time_limit
      t.index :name, unique: true
    end

    create_table :"octo.slurm_snapshots", id: :bigserial do |t|
      t.datetime :captured_at,   null: false, default: -> { "NOW()" }
      t.text     :source_cmd,    null: false, default: 'sinfo -a'
      t.text     :raw_text,      null: false
      t.text     :parser_version, null: false, default: 'v1'
    end
    add_index :"octo.slurm_snapshots",
              :captured_at,
              order: { captured_at: :desc },
              name: "idx_slurm_snapshots_captured_at"

    create_table :"octo.slurm_nodes", id: :bigserial do |t|
      t.text    :hostname, null: false
      t.text    :prefix,   null: false
      t.integer :number
      t.index :hostname, unique: true
      t.index [:prefix, :number], name: "idx_slurm_nodes_prefix_number"
    end

    create_table :"octo.slurm_node_snapshot", id: false do |t|
      t.bigint  :snapshot_id,  null: false
      t.bigint  :node_id,      null: false
      t.integer :partition_id, null: false
      t.column  :state, :"octo.slurm_node_state", null: false
      t.boolean :has_reason, null: false, default: false
    end

    add_foreign_key :"octo.slurm_node_snapshot", :"octo.slurm_snapshots",  column: :snapshot_id,  on_delete: :cascade
    add_foreign_key :"octo.slurm_node_snapshot", :"octo.slurm_nodes",      column: :node_id,      on_delete: :restrict
    add_foreign_key :"octo.slurm_node_snapshot", :"octo.slurm_partitions", column: :partition_id, on_delete: :restrict

    add_index :"octo.slurm_node_snapshot",
              [:snapshot_id, :node_id],
              unique: true,
              name: "idx_node_snapshot_unique_snapshot_node"

    add_index :"octo.slurm_node_snapshot",
              [:partition_id, :state],
              name: "idx_node_snapshot_partition_state"
  end

  def down
    drop_table :"octo.slurm_node_snapshot"
    drop_table :"octo.slurm_nodes"
    drop_table :"octo.slurm_snapshots"
    drop_table :"octo.slurm_partitions"

    execute %(DROP TYPE IF EXISTS "octo".slurm_node_state;)
    execute %(DROP SCHEMA IF EXISTS "octo" CASCADE;)
  end
end

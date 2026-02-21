class AddClusterToCoreComments < ActiveRecord::Migration[5.2]
  def up
    add_reference :core_comments,
                  :cluster,
                  null: true,
                  type: :integer,
                  foreign_key: { to_table: :core_clusters },
                  index: true

    default_cluster = Core::Cluster.order(:id).first
    raise "No clusters found in core_clusters; cannot backfill core_comments.cluster_id" unless default_cluster

    Core::Comments::Comment.where(cluster_id: nil).update_all(cluster_id: default_cluster.id)

    change_column_null :core_comments, :cluster_id, false
  end

  def down
    remove_reference :core_comments, :cluster, foreign_key: { to_table: :core_clusters }
  end
end

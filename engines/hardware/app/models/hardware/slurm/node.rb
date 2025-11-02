module Hardware
  module Slurm
    class Node < ApplicationRecord
      self.table_name = 'hardware_slurm_nodes'
      has_many :node_snapshots, class_name: 'Hardware::Slurm::NodeSnapshot',
                                foreign_key: :slurm_node_id,
                                dependent: :destroy
      validates :hostname, presence: true, uniqueness: true
      validates :prefix,   presence: true
    end
  end
end

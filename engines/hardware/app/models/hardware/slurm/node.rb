module Hardware
  module Slurm
    class Node < ApplicationRecord
      self.table_name = 'hardware_slurm_nodes'
      belongs_to :system, class_name: 'Hardware::Slurm::System'
      has_many :node_states, class_name: 'Hardware::Slurm::NodeState',
                             foreign_key: :slurm_node_id, dependent: :destroy
      validates :hostname, presence: true, uniqueness: { scope: :system_id }
      validates :prefix,   presence: true
    end
  end
end

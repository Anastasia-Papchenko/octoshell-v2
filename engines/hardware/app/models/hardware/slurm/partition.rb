module Hardware
  module Slurm
    class Partition < ApplicationRecord
      self.table_name = 'hardware_slurm_partitions'
      belongs_to :system, class_name: 'Hardware::Slurm::System'
      has_many :node_states, class_name: 'Hardware::Slurm::NodeState',
                             foreign_key: :slurm_partition_id
      validates :name, presence: true, uniqueness: { scope: :system_id }
    end
  end
end

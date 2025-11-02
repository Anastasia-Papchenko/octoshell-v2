module Hardware
  module Slurm
    class Partition < ApplicationRecord
      self.table_name = 'hardware_slurm_partitions'
      has_many :node_snapshots, class_name: 'Hardware::Slurm::NodeSnapshot',
                                foreign_key: :slurm_partition_id
      validates :name, presence: true, uniqueness: true
    end
  end
end

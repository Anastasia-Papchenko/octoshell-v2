module Hardware
  module Slurm
    class System < ApplicationRecord
      self.table_name = 'hardware_slurm_systems'
      has_many :nodes,       class_name: 'Hardware::Slurm::Node',       foreign_key: :system_id, dependent: :destroy
      has_many :partitions,  class_name: 'Hardware::Slurm::Partition',  foreign_key: :system_id, dependent: :destroy
      has_many :snapshots,   class_name: 'Hardware::Slurm::Snapshot',   foreign_key: :system_id, dependent: :destroy
      has_many :node_states, class_name: 'Hardware::Slurm::NodeState',  foreign_key: :system_id, dependent: :destroy

      validates :name, :slug, presence: true
      validates :name, :slug, uniqueness: true
    end
  end
end

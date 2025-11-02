module Hardware
  module Slurm
    class NodeSnapshot < ApplicationRecord
      self.table_name = 'hardware_slurm_node_snapshots'

      STATES    = %w[alloc idle comp drain drng down maint reserved mix].freeze
      SUBSTATES = %w[unknown maintenance pending draining].freeze

      belongs_to :slurm_snapshot,  class_name: 'Hardware::Slurm::Snapshot'
      belongs_to :slurm_node,      class_name: 'Hardware::Slurm::Node'
      belongs_to :slurm_partition, class_name: 'Hardware::Slurm::Partition'

      validates :state, presence: true, inclusion: { in: STATES }
      validates :substate, allow_nil: true, inclusion: { in: SUBSTATES }
      validates :has_reason, inclusion: { in: [true, false] }

      scope :for_snapshot, ->(sid) { where(slurm_snapshot_id: sid) }
      scope :by_state,     ->(st)  { where(state: st) }
    end
  end
end

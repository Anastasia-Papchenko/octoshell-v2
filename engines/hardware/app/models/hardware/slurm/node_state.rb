module Hardware
  module Slurm
    class NodeState < ApplicationRecord
      self.table_name = 'hardware_slurm_node_states'

      STATES    = %w[alloc idle comp drain drng down maint reserved mix].freeze
      SUBSTATES = %w[unknown maintenance pending draining].freeze

      belongs_to :system,          class_name: 'Hardware::Slurm::System'
      belongs_to :slurm_snapshot,  class_name: 'Hardware::Slurm::Snapshot'
      belongs_to :slurm_node,      class_name: 'Hardware::Slurm::Node'
      belongs_to :slurm_partition, class_name: 'Hardware::Slurm::Partition'

      validates :state, presence: true, inclusion: { in: STATES }
      validates :substate, allow_nil: true, inclusion: { in: SUBSTATES }
      validates :has_reason, inclusion: { in: [true, false] }
      validates :valid_from, presence: true

      scope :current, -> { where(valid_to: nil) }
      scope :at, ->(ts) { where("valid_from <= ? AND (valid_to IS NULL OR valid_to > ?)", ts, ts) }
    end
  end
end

module Hardware
  module Slurm
    class Snapshot < ApplicationRecord
      self.table_name = 'hardware_slurm_snapshots'
      belongs_to :system, class_name: 'Hardware::Slurm::System'
      has_many :node_states, class_name: 'Hardware::Slurm::NodeState',
                             foreign_key: :slurm_snapshot_id, dependent: :destroy
      scope :latest_first, -> { order(captured_at: :desc) }
      validates :captured_at, :source_cmd, :parser_version, :raw_text, presence: true
    end
  end
end

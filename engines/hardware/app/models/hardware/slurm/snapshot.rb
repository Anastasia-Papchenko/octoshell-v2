module Hardware
  module Slurm
    class Snapshot < ApplicationRecord
      self.table_name = 'hardware_slurm_snapshots'
      has_many :node_snapshots, class_name: 'Hardware::Slurm::NodeSnapshot',
                                foreign_key: :slurm_snapshot_id,
                                dependent: :destroy
      scope :latest_first, -> { order(captured_at: :desc) }
      validates :captured_at, :source_cmd, :parser_version, :raw_text, presence: true
    end
  end
end

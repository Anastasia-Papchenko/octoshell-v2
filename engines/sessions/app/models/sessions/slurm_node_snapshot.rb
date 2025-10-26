module Sessions
  class SlurmNodeSnapshot < ApplicationRecord
    belongs_to :snapshot
    belongs_to :node
    belongs_to :partition
  end
end

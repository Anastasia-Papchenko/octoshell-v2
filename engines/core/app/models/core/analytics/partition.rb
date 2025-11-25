module Core
  module Analytics
    class Partition < ApplicationRecord
      self.table_name = 'core_analytics_partitions'
      belongs_to :system, class_name:    'Core::Analytics::System'
      has_many :node_states, class_name: 'Core::Analytics::NodeState', foreign_key: :partition_id
      
      validates :name, presence: true, uniqueness: { scope: :system_id }
    end
  end
end

# module Core
#   module Analytics
#     class Partition < ApplicationRecord
#       self.table_name = 'core_analytics_partitions'
#       belongs_to :cluster,
#                   class_name: 'Core::Cluster',
#                   foreign_key: :system_id,
#                   primary_key: :analytics_system_id

#       def system
#         cluster
#       end

#       def system=(v)
#         self.cluster = v
#       end

#       has_many :node_states, class_name: 'Core::Analytics::NodeState', foreign_key: :partition_id
      
#       validates :name, presence: true, uniqueness: { scope: :system_id }
#     end
#   end
# end

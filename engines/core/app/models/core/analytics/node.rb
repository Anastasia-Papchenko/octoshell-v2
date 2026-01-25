module Core
  module Analytics
    class Node < ApplicationRecord
      self.table_name = 'core_analytics_nodes'
      #belongs_to :system, class_name:    'Core::Analytics::System'
      belongs_to :system, class_name:    'Core::Cluster'
      # belongs_to :cluster
      has_many :node_states, class_name: 'Core::Analytics::NodeState', foreign_key: :node_id, dependent: :destroy
      
      validates :hostname, presence: true, uniqueness: { scope: :system_id }
      validates :prefix,   presence: true
    end
  end
end

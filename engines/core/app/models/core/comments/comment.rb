module Core
  module Comments
    class Comment < ApplicationRecord
      self.table_name = 'core_comments'

      belongs_to :author,
                 class_name: '::User',
                 foreign_key: :author_id,
                 inverse_of: :comments

      belongs_to :cluster, class_name: 'Core::Cluster'

      
      def system
        cluster
      end

      def system=(v)
        self.cluster = v
      end

      has_many :comment_nodes,
               class_name: 'Core::Comments::CommentNode',
               foreign_key: :comment_id,
               inverse_of: :comment,
               dependent: :destroy

      has_many :nodes,
               through: :comment_nodes,
               class_name: 'Core::Analytics::Node',
               source: :node

      has_many :comment_tags,
               class_name: 'Core::Comments::CommentTag',
               foreign_key: :comment_id,
               inverse_of: :comment,
               dependent: :destroy

      has_many :tags,
               through: :comment_tags,
               class_name: 'Core::Comments::Tag',
               source: :tag

      enum :severity, {
        info: 0,
        warning: 1,
        incident: 2
      }, prefix: :severity

      validates :title, presence: true
      validates :valid_from, presence: true
      validates :severity, presence: true
      validates :system, presence: true
      validates :author, presence: true

      validate :valid_to_not_before_valid_from

      scope :recent_first, -> { order(valid_from: :desc, created_at: :desc) }
      scope :current, ->(moment = Time.current) {
        where('valid_from <= ? AND (valid_to IS NULL OR valid_to >= ?)', moment, moment)
      }

      private

      def valid_to_not_before_valid_from
        return if valid_to.blank? || valid_from.blank?
        errors.add(:valid_to, 'не может быть раньше даты начала действия') if valid_to < valid_from
      end
    end
  end
end
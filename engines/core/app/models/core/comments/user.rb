module Core
  module Comments
    class User < ApplicationRecord
      self.table_name = 'core_comments_users'

      has_many :comments,
               class_name: 'Core::Comments::Comment',
               foreign_key: :author_id,
               inverse_of: :author,
               dependent: :nullify

      validates :email, presence: true, uniqueness: true
    end
  end
end

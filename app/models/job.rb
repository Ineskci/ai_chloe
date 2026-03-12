class Job < ApplicationRecord
  has_many :chats, dependent: :destroy
end

class Chat < ApplicationRecord
  belongs_to :users
  belongs_to :jobs
  has_many :messages, dependent: :destroy
end

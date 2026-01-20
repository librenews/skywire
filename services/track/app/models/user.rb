class User < ApplicationRecord
  has_many :tracks, dependent: :destroy
  has_secure_token :feed_token

  validates :did, presence: true, uniqueness: true
end

class Delivery < ApplicationRecord
  belongs_to :track

  # STI Base Class
  validates :type, presence: true
end

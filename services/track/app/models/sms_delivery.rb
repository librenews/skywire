class SmsDelivery < Delivery
  validates :phone, presence: true
end

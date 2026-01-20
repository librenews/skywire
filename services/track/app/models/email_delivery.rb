class EmailDelivery < Delivery
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :frequency, presence: true, inclusion: { in: %w[instant daily weekly] }
end

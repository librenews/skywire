class WebhookDelivery < Delivery
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp }
end

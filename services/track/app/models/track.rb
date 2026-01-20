class Track < ApplicationRecord
  belongs_to :user
  has_many :matches, dependent: :destroy
  has_many :deliveries, dependent: :destroy

  before_validation :set_default_name
  before_validation :generate_external_id, on: :create

  validates :name, presence: true
  validates :external_id, presence: true, uniqueness: true, on: :create
  validate :query_or_keywords_present
  validates :threshold, presence: true, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 }
  validates :status, presence: true

  enum :status, { pending: "pending", active: "active", error: "error", inactive: "inactive" }, default: "pending"

  STOPWORDS = %w[
    a an the and or but if then else when at on in to for from with by about
    as of that this these those it he she they we you i me my mine yours ours
    theirs his hers its who whom whose which what where why how be am is are
    was were been being have has had having do does did doing will would shall
    should can could may might must ought
  ].freeze

  validate :validate_keywords_are_not_stopwords
  
  def track_type
    if query.present? && keywords.present?
      "Mixed"
    elsif query.present?
      "Semantic"
    elsif keywords.present?
      "Keyword"
    else
      "Unknown"
    end
  end

  def volume_7d
    # Caching these later is a good idea
    matches.where("created_at > ?", 7.days.ago).count
  end

  def last_match_at
    matches.order(created_at: :desc).limit(1).pluck(:created_at).first
  end

  def to_param
    external_id
  end

  private

  def set_default_name
    return if name.present?

    self.name =
      name_from_keywords ||
      name_from_query ||
      "Untitled Track"
  end

  def name_from_keywords
    return if keywords.blank?

    keywords
      .first(3)
      .map(&:to_s)
      .map(&:strip)
      .reject(&:blank?)
      .map(&:capitalize)
      .join(" ")
      .presence
  end

  def name_from_query
    return if query.blank?

    words = query
      .downcase
      .gsub(/[^a-z0-9\s]/, "")
      .split
      .reject { |w| STOPWORDS.include?(w) }
      .uniq

    # Take the first few meaningful words
    words
      .first(4)
      .map(&:capitalize)
      .join(" ")
      .presence
  end
  
  def generate_external_id
    self.external_id ||= SecureRandom.uuid
  end

  def query_or_keywords_present
    if query.blank? && keywords.blank?
      errors.add(:base, "You must provide either a search query or at least one keyword.")
    end
  end

  def validate_keywords_are_not_stopwords
    return if keywords.blank?

    keywords.each do |keyword|
      if STOPWORDS.include?(keyword.downcase.strip)
        errors.add(:keywords, "contains a stopword: '#{keyword}'. Please use more specific terms.")
      end
    end
  end
end

require "test_helper"

class TrackTest < ActiveSupport::TestCase
  test "valid factory" do
    track = tracks(:one)
    assert track.valid?
  end

  test "generates external_id on creation" do
    track = Track.create(user: users(:one), query: "test", threshold: 0.5)
    assert_not_nil track.external_id
    assert_match /[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/, track.external_id
  end

  test "validates threshold range" do
    track = Track.new(user: users(:one), query: "test")

    track.threshold = -0.1
    assert_not track.valid?

    track.threshold = 1.1
    assert_not track.valid?

    track.threshold = 0.5
    assert track.valid?
  end

  test "validates query or keywords presence" do
    track = Track.new(user: users(:one), threshold: 0.5)
    assert_not track.valid?
    assert_includes track.errors[:base], "You must provide either a search query or at least one keyword."

    # Valid with query only
    track.query = "something"
    assert track.valid?

    # Valid with keywords only
    track.query = nil
    track.keywords = [ "something" ]
    assert track.valid?
  end

  test "validates keywords against stopwords" do
    track = Track.new(user: users(:one), query: "test")

    # Exact match lower case
    track.keywords = [ "the" ]
    assert_not track.valid?
    assert_includes track.errors[:keywords].join, "contains a stopword: 'the'"

    # Mixed case and whitespace
    track.keywords = [ "  And  " ]
    assert_not track.valid?
    assert_includes track.errors[:keywords].join, "contains a stopword: '  And  '"

    # Valid keyword
    track.keywords = [ "ruby" ]
    assert track.valid?
  end
end

require "test_helper"

class MatchMailerTest < ActionMailer::TestCase
  test "new_match" do
    mail = MatchMailer.new_match
    assert_equal "New match", mail.subject
    assert_equal [ "to@example.org" ], mail.to
    assert_equal [ "from@example.com" ], mail.from
    assert_match "Hi", mail.body.encoded
  end
end

# Preview all emails at http://localhost:3000/rails/mailers/match_mailer
class MatchMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/match_mailer/new_match
  def new_match
    MatchMailer.new_match
  end
end

class MatchMailer < ApplicationMailer
  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.match_mailer.new_match.subject
  #
  def new_match(delivery, match)
    @match = match
    @track = match.track
    @post = match.data

    mail to: delivery.email, subject: "New Match found for: #{@track.name}"
  end
end

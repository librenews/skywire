class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "notify@bsky.track.social")
  default reply_to: ENV.fetch("MAILER_REPLY_TO", "app@track.social")
  layout "mailer"
end

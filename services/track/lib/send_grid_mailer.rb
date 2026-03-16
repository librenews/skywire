require 'sendgrid-ruby'

class SendGridMailer
  include SendGrid

  def initialize(settings)
    @api_key = settings[:api_key]
  end

  def deliver!(mail)
    from = Email.new(email: mail.from.first)
    to = Email.new(email: mail.to.first)
    subject = mail.subject
    content = Content.new(type: 'text/html', value: mail.body.raw_source)
    
    mail = Mail.new(from, subject, to, content)
    
    # Optional Reply-To
    if mail.reply_to
      mail.reply_to = Email.new(email: mail.reply_to.first)
    end

    sg = SendGrid::API.new(api_key: @api_key)
    response = sg.client.mail._('send').post(request_body: mail.to_json)

    if response.status_code.to_i >= 400
      raise "SendGrid API Error: #{response.status_code} - #{response.body}"
    end
  end
end

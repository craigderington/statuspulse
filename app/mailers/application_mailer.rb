class ApplicationMailer < ActionMailer::Base
  # Must align with the verified Mailgun sending domain, which is a subdomain
  # (mg.statuspulse.org) for some accounts — a mismatch fails DKIM/SPF alignment.
  default from: ENV.fetch("MAIL_FROM", "StatusPulse <noreply@statuspulse.org>")
  layout "mailer"
end

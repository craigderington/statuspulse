# Register the Mailgun HTTP API delivery method with ActionMailer.
#
# Required explicitly rather than autoloaded: delivery methods are registered at
# boot, and referencing an autoloaded constant here would break eager loading in
# production.
require Rails.root.join("lib/mailgun_api_delivery")

# Settings are passed as add_delivery_method defaults rather than set via
# `config.action_mailer.mailgun_api_settings` in production.rb. ActionMailer's
# railtie applies config.action_mailer.* through a load hook registered before
# this file runs, so a `mailgun_api_settings=` there would be called before
# add_delivery_method has defined that accessor — boot fails with NoMethodError.
ActiveSupport.on_load(:action_mailer) do
  add_delivery_method :mailgun_api, MailgunApiDelivery,
    api_key: ENV["MAILGUN_API_KEY"],
    domain: ENV.fetch("MAILGUN_DOMAIN", "statuspulse.org"),
    # EU-region Mailgun accounts must set MAILGUN_API_BASE to https://api.eu.mailgun.net
    api_base: ENV.fetch("MAILGUN_API_BASE", "https://api.mailgun.net")
end

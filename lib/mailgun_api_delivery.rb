# ActionMailer delivery method that posts messages to the Mailgun HTTP API
# instead of speaking SMTP.
#
# Chosen over SMTP because AWS restricts outbound SMTP on Lightsail/EC2 by
# default, while the API is ordinary HTTPS on 443. It also returns a Mailgun
# message ID, which is correlatable against Mailgun's logs and webhooks.
#
# Uses the /messages.mime endpoint so the MIME document ActionMailer already
# built is sent verbatim — multipart alternatives, headers and encodings all
# survive untouched.
require "net/http"
require "uri"
require "securerandom"

class MailgunApiDelivery
  class DeliveryError < StandardError; end

  DEFAULT_API_BASE = "https://api.mailgun.net".freeze
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 20

  attr_reader :settings

  def initialize(settings = {})
    @settings = settings || {}
  end

  def deliver!(mail)
    api_key = presence(settings[:api_key])
    raise DeliveryError, "Mailgun API key is not configured (set MAILGUN_API_KEY)" unless api_key

    domain = presence(settings[:domain])
    raise DeliveryError, "Mailgun domain is not configured (set MAILGUN_DOMAIN)" unless domain

    recipients = Array(mail.destinations).reject { |r| presence(r).nil? }
    raise DeliveryError, "Message has no recipients" if recipients.empty?

    post(api_key, domain, recipients, mail.to_s)
  end

  private

  def post(api_key, domain, recipients, mime)
    uri = URI.parse("#{api_base}/v3/#{domain}/messages.mime")
    boundary = "----statuspulse-#{SecureRandom.hex(12)}"

    request = Net::HTTP::Post.new(uri)
    request.basic_auth("api", api_key)
    request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
    request.body = multipart_body(boundary, recipients, mime)

    response = Net::HTTP.start(
      uri.hostname, uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: OPEN_TIMEOUT,
      read_timeout: READ_TIMEOUT
    ) { |http| http.request(request) }

    unless response.is_a?(Net::HTTPSuccess)
      raise DeliveryError, "Mailgun API responded #{response.code}: #{response.body.to_s[0, 500]}"
    end

    response
  end

  # Mailgun needs the envelope recipients as repeated `to` fields; the message
  # itself rides along as a file part named `message`.
  def multipart_body(boundary, recipients, mime)
    parts = recipients.map do |recipient|
      "--#{boundary}\r\n" \
      "Content-Disposition: form-data; name=\"to\"\r\n\r\n" \
      "#{recipient}\r\n"
    end

    parts << "--#{boundary}\r\n" \
             "Content-Disposition: form-data; name=\"message\"; filename=\"message.mime\"\r\n" \
             "Content-Type: application/octet-stream\r\n\r\n" \
             "#{mime}\r\n"
    parts << "--#{boundary}--\r\n"
    parts.join
  end

  def api_base
    presence(settings[:api_base]) || DEFAULT_API_BASE
  end

  def presence(value)
    return nil if value.nil?

    string = value.to_s.strip
    string.empty? ? nil : string
  end
end

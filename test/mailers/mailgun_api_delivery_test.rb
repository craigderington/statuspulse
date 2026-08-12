require "test_helper"
require Rails.root.join("lib/mailgun_api_delivery")

class MailgunApiDeliveryTest < ActiveSupport::TestCase
  def build_mail(to: "ops@example.test")
    Mail.new do
      from    "reports@statuspulse.org"
      to      to
      subject "Weekly Uptime Digest"
      body    "99.98% uptime"
    end
  end

  def valid_settings(overrides = {})
    { api_key: "key-test", domain: "statuspulse.org" }.merge(overrides)
  end

  test "raises when the api key is missing" do
    delivery = MailgunApiDelivery.new(domain: "statuspulse.org")

    error = assert_raises(MailgunApiDelivery::DeliveryError) { delivery.deliver!(build_mail) }
    assert_match(/MAILGUN_API_KEY/, error.message)
  end

  test "raises when the api key is blank rather than sending unauthenticated" do
    delivery = MailgunApiDelivery.new(valid_settings(api_key: "   "))

    assert_raises(MailgunApiDelivery::DeliveryError) { delivery.deliver!(build_mail) }
  end

  test "raises when the domain is missing" do
    delivery = MailgunApiDelivery.new(api_key: "key-test")

    error = assert_raises(MailgunApiDelivery::DeliveryError) { delivery.deliver!(build_mail) }
    assert_match(/MAILGUN_DOMAIN/, error.message)
  end

  test "raises when the message has no recipients" do
    delivery = MailgunApiDelivery.new(valid_settings)
    mail = build_mail(to: nil)

    error = assert_raises(MailgunApiDelivery::DeliveryError) { delivery.deliver!(mail) }
    assert_match(/no recipients/i, error.message)
  end

  test "multipart body carries every envelope recipient as a separate to field" do
    delivery = MailgunApiDelivery.new(valid_settings)
    mail = build_mail(to: [ "a@example.test", "b@example.test" ])
    mail.cc = "c@example.test"

    body = delivery.send(:multipart_body, "BOUND", mail.destinations, mail.to_s)

    assert_equal 3, body.scan(/name="to"/).length
    assert_includes body, "a@example.test"
    assert_includes body, "b@example.test"
    assert_includes body, "c@example.test"
  end

  test "multipart body sends the mime document verbatim as the message part" do
    delivery = MailgunApiDelivery.new(valid_settings)
    mail = build_mail

    body = delivery.send(:multipart_body, "BOUND", mail.destinations, mail.to_s)

    assert_includes body, 'name="message"; filename="message.mime"'
    assert_includes body, "Subject: Weekly Uptime Digest"
    assert_includes body, "99.98% uptime"
    assert body.end_with?("--BOUND--\r\n"), "multipart body must be terminated by the closing boundary"
  end

  test "defaults to the US api base but honours an override for the EU region" do
    assert_equal "https://api.mailgun.net", MailgunApiDelivery.new(valid_settings).send(:api_base)

    eu = MailgunApiDelivery.new(valid_settings(api_base: "https://api.eu.mailgun.net"))
    assert_equal "https://api.eu.mailgun.net", eu.send(:api_base)
  end
end

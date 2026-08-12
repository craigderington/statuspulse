require "test_helper"
require Rails.root.join("lib/mailgun_api_delivery")

# The From: address must stay on the verified Mailgun sending domain, and the
# display-name form must survive into the MIME document the API receives.
class MailFromTest < ActiveSupport::TestCase
  test "a display-name sender is preserved in the encoded MIME" do
    mail = Mail.new do
      from    "StatusPulse Reports <reports@mg.statuspulse.org>"
      to      "ops@example.test"
      subject "Weekly Uptime Digest"
      body    "99.98% uptime"
    end

    mime = mail.to_s

    assert_includes mime, "From: StatusPulse Reports <reports@mg.statuspulse.org>"
    assert_equal [ "reports@mg.statuspulse.org" ], mail.from
  end

  test "the delivery envelope uses recipients, not the display-name sender" do
    delivery = MailgunApiDelivery.new(api_key: "key-test", domain: "mg.statuspulse.org")
    mail = Mail.new do
      from    "StatusPulse Reports <reports@mg.statuspulse.org>"
      to      "ops@example.test"
      subject "Weekly Uptime Digest"
      body    "99.98% uptime"
    end

    body = delivery.send(:multipart_body, "BOUND", mail.destinations, mail.to_s)

    assert_equal 1, body.scan(/name="to"/).length
    assert_includes body, "ops@example.test"
    assert_not_includes body.split('name="message"').first, "reports@mg.statuspulse.org"
  end
end

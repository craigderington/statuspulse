require "test_helper"

class WeeklyDigestMailerTest < ActionMailer::TestCase
  test "digest_email" do
    org = Organization.create!(name: "Mailer Test Org", slug: "mailer-test-org")
    User.create!(name: "Recipient", email: "user@mailertest.com", password: "password123", password_confirmation: "password123", organization: org)

    email = WeeklyDigestMailer.digest_email(org)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [ "user@mailertest.com" ], email.to
    assert_includes email.subject, "Weekly Uptime Digest"
  end
end

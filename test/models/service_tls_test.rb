require "test_helper"

class ServiceTlsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @org = Organization.create!(name: "Northwind", slug: "northwind-tls")
    @org.users.create!(
      name: "Ops", email: "ops@northwind-tls.test", role: "admin",
      password: "a-long-enough-password", password_confirmation: "a-long-enough-password"
    )
    @service = @org.services.create!(
      name: "Core API", url: "https://example.test/health", http_method: "GET",
      expected_status_code: 200, timeout_seconds: 10, status: "operational",
      check_interval_seconds: 60
    )
  end

  # Builds a self-signed certificate with a chosen expiry, so the recording path
  # is exercised with a real OpenSSL object rather than a stub.
  def certificate(expires_in:, issuer: "Test CA")
    key = OpenSSL::PKey::RSA.new(1024)
    cert = OpenSSL::X509::Certificate.new
    cert.subject = OpenSSL::X509::Name.parse("/CN=example.test")
    cert.issuer = OpenSSL::X509::Name.parse("/CN=#{issuer}")
    cert.not_before = 1.day.ago
    cert.not_after = expires_in.from_now
    cert.public_key = key.public_key
    cert.serial = 1
    cert.version = 2
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    cert
  end

  # ---- verification default ----

  test "certificates are verified by default" do
    assert @service.verify_tls?,
      "not verifying means an expired or mismatched certificate passes while a browser refuses"
  end

  test "verification can be turned off for a self-signed or internal endpoint" do
    @service.update!(verify_tls: false)

    assert_not @service.reload.verify_tls?
  end

  # ---- recording ----

  test "records expiry and issuer from the certificate" do
    @service.record_certificate!(certificate(expires_in: 60.days, issuer: "Lets Encrypt"))
    @service.reload

    assert_in_delta 60.days.from_now, @service.tls_expires_at, 60
    assert_equal "Lets Encrypt", @service.tls_issuer
    assert @service.tls_monitored?
  end

  test "a nil certificate is ignored rather than raising" do
    assert_nothing_raised { @service.record_certificate!(nil) }
    assert_nil @service.reload.tls_expires_at
  end

  # ---- windows ----

  test "a certificate well inside its life is not a problem" do
    @service.record_certificate!(certificate(expires_in: 60.days))
    @service.reload

    assert_not @service.tls_expiring_soon?
    assert_not @service.tls_expired?
    assert_equal 59, @service.tls_days_remaining
  end

  test "a certificate inside the warning window is expiring soon" do
    @service.record_certificate!(certificate(expires_in: 10.days))
    @service.reload

    assert @service.tls_expiring_soon?
    assert_not @service.tls_expired?
  end

  test "an expired certificate is expired, not merely expiring" do
    @service.update_columns(tls_expires_at: 2.days.ago)

    assert @service.tls_expired?
    assert_not @service.tls_expiring_soon?
  end

  # ---- status ----

  test "an expiring certificate degrades the service" do
    @service.update_columns(tls_expires_at: 5.days.from_now)

    assert_equal "degraded", @service.send(:determine_new_status, true, 100)
  end

  test "an expired certificate takes the service down" do
    @service.update_columns(tls_expires_at: 1.day.ago)

    assert_equal "outage", @service.send(:determine_new_status, true, 100)
  end

  test "a healthy certificate leaves the status alone" do
    @service.update_columns(tls_expires_at: 90.days.from_now)

    assert_equal "operational", @service.send(:determine_new_status, true, 100)
  end

  # ---- alerting ----

  test "entering the warning window alerts once, not on every check" do
    assert_enqueued_with(job: ServiceAlertJob) do
      @service.record_certificate!(certificate(expires_in: 10.days))
    end

    assert_no_enqueued_jobs(only: ServiceAlertJob) do
      3.times { @service.reload.record_certificate!(certificate(expires_in: 10.days)) }
    end
  end

  test "a healthy certificate alerts nobody" do
    assert_no_enqueued_jobs(only: ServiceAlertJob) do
      @service.record_certificate!(certificate(expires_in: 90.days))
    end
  end

  test "renewing re-arms the warning for the next certificate" do
    @service.record_certificate!(certificate(expires_in: 10.days))
    assert_not_nil @service.reload.tls_alerted_at

    # Renewed: a different expiry means a different certificate.
    @service.record_certificate!(certificate(expires_in: 90.days))
    assert_nil @service.reload.tls_alerted_at,
      "a renewal must re-arm the warning, or the next expiry passes silently"
  end

  test "a workspace with alerts disabled is not told about certificates either" do
    @org.update!(alerts_enabled: false)

    assert_no_enqueued_jobs(only: ServiceAlertJob) do
      @service.record_certificate!(certificate(expires_in: 3.days))
    end
  end
end

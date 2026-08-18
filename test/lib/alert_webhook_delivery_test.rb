require "test_helper"
require Rails.root.join("lib/alert_webhook_delivery")

# The webhook URL is set by any tenant and this code runs on a server inside a
# cloud network with a metadata endpoint and a private subnet. The destination
# is validated, not trusted.
class AlertWebhookDeliveryTest < ActiveSupport::TestCase
  setup do
    @org = Organization.new(name: "Northwind", slug: "northwind-webhook",
                            alert_webhook_secret: "test-secret")
    @delivery = AlertWebhookDelivery.new(@org)
  end

  def validate(url)
    @delivery.send(:validated_uri, url)
    :allowed
  rescue AlertWebhookDelivery::UnsafeDestination => e
    e.message
  end

  test "rejects plaintext http" do
    assert_match(/must use https/, validate("http://example.com/hook"))
  end

  test "rejects non-http schemes" do
    assert_match(/must use https/, validate("file:///etc/passwd"))
    assert_match(/must use https/, validate("gopher://example.com/"))
  end

  test "rejects the cloud metadata endpoint" do
    assert_match(/private or reserved/, validate("https://169.254.169.254/latest/meta-data/"))
  end

  test "rejects loopback" do
    assert_match(/private or reserved/, validate("https://127.0.0.1/hook"))
    assert_match(/private or reserved/, validate("https://[::1]/hook"))
  end

  test "rejects private ranges" do
    %w[
      https://10.0.0.5/hook
      https://172.16.0.1/hook
      https://192.168.1.10/hook
      https://[fc00::1]/hook
      https://[fe80::1]/hook
    ].each do |url|
      assert_match(/private or reserved/, validate(url), "#{url} must be rejected")
    end
  end

  test "rejects a malformed url" do
    assert_match(/not a valid URL/, validate("not a url"))
  end

  test "allows an ordinary public https endpoint" do
    assert_equal :allowed, validate("https://93.184.216.34/hook")
  end

  test "the signature covers the timestamp as well as the body" do
    a = @delivery.signature(1_000, '{"a":1}')
    b = @delivery.signature(1_001, '{"a":1}')
    c = @delivery.signature(1_000, '{"a":2}')

    assert_equal a, @delivery.signature(1_000, '{"a":1}'), "must be deterministic"
    assert_not_equal a, b, "a different timestamp must change the signature"
    assert_not_equal a, c, "a different body must change the signature"
    assert_match(/\Av1=[0-9a-f]{64}\z/, a)
  end

  test "the signature depends on the workspace secret" do
    other = Organization.new(name: "Other", slug: "other", alert_webhook_secret: "different")

    assert_not_equal @delivery.signature(1_000, "{}"),
                     AlertWebhookDelivery.new(other).signature(1_000, "{}")
  end

  # ---- form-time validation: no DNS, so settings stay saveable ----

  test "form validation rejects unsafe schemes and literal private addresses" do
    [
      [ "http://example.com/hook", /must use https/ ],
      [ "file:///etc/passwd", /must use https/ ],
      [ "https://127.0.0.1/hook", /private or reserved/ ],
      [ "https://169.254.169.254/", /private or reserved/ ],
      [ "https://[::1]/hook", /private or reserved/ ],
      [ "not a url", /not a valid URL/ ]
    ].each do |url, pattern|
      error = assert_raises(AlertWebhookDelivery::UnsafeDestination, "#{url} must be rejected") do
        AlertWebhookDelivery.validate_format!(url)
      end
      assert_match pattern, error.message
    end
  end

  test "form validation accepts a hostname without resolving it" do
    # A host that does not resolve must still save: settings have to remain
    # editable when the configured endpoint is down, not least to turn alerts off.
    assert_nothing_raised do
      AlertWebhookDelivery.validate_format!("https://hooks.example-does-not-exist.invalid/statuspulse")
    end
  end

  test "a workspace can be saved while its webhook host is unresolvable" do
    org = Organization.create!(name: "Northwind", slug: "northwind-unresolvable",
                               alert_webhook_url: "https://hooks.example-does-not-exist.invalid/hook")

    assert org.persisted?
    assert org.update(alerts_enabled: false), "must be able to turn alerts off regardless of webhook health"
  end

  test "the payload describes the event without leaking other tenants" do
    org = Organization.create!(name: "Northwind", slug: "northwind-payload")
    service = org.services.create!(
      name: "Core API", url: "https://example.test/health", http_method: "GET",
      expected_status_code: 200, timeout_seconds: 10, status: "outage",
      check_interval_seconds: 60, last_status_code: 502, last_response_time_ms: 143
    )

    payload = AlertWebhookDelivery.new(org).send(:payload, "down", service, "Expected HTTP 200, got 502", nil)

    assert_equal "service.down", payload[:event]
    assert_equal "northwind-payload", payload[:organization][:slug]
    assert_equal service.id, payload[:service][:id]
    assert_equal 502, payload[:service][:last_status_code]
    assert_equal "Expected HTTP 200, got 502", payload[:error_message]
  end
end

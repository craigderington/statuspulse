require "net/http"
require "uri"
require "json"
require_relative "outbound_http_destination"

# Posts an alert to a customer-supplied webhook URL.
#
# The URL is attacker-controllable in the sense that matters here: any tenant
# can set it to anything, and this code runs on a server inside a cloud network
# with an instance metadata endpoint and a private subnet. So the destination is
# validated rather than trusted, and requests are pinned to the address that was
# validated to close the DNS-rebinding gap between the check and the connection.
class AlertWebhookDelivery
  class DeliveryError < StandardError; end
  class UnsafeDestination < DeliveryError; end

  TIMEOUT = 5
  MAX_REDIRECTS = 0

  # Cloud metadata, loopback, private and link-local space. A webhook pointed
  # here is either a mistake or an attempt to make the server talk to something
  # only it can reach.
  # Form-time validation. Deliberately does NO name resolution: a model
  # validation that performs DNS is slow, fails when DNS does, and would block
  # saving unrelated settings — including turning alerts off — whenever the
  # configured host happens to be unreachable. The authoritative check happens
  # at delivery, where the address is also pinned.
  #
  # Literal addresses are still rejected here, since that costs nothing.
  def self.validate_format!(raw)
    OutboundHttpDestination.validate_format!(raw, https_only: true)
  rescue OutboundHttpDestination::UnsafeDestination => e
    raise UnsafeDestination, e.message
  end

  def initialize(organization)
    @organization = organization
  end

  def deliver!(kind:, service:, error_message: nil, downtime_started_at: nil)
    uri = validated_uri(@organization.alert_webhook_url)
    body = payload(kind, service, error_message, downtime_started_at).to_json
    timestamp = Time.current.to_i

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["User-Agent"] = "StatusPulse-Alerts/1.0 (+https://statuspulse.org)"
    request["X-StatusPulse-Event"] = event_name(kind)
    request["X-StatusPulse-Timestamp"] = timestamp.to_s
    request["X-StatusPulse-Signature"] = signature(timestamp, body)
    request.body = body

    response = perform(uri, request)

    unless response.is_a?(Net::HTTPSuccess)
      raise DeliveryError, "webhook responded #{response.code}"
    end

    response
  end

  # The signature covers the timestamp as well as the body, so a captured
  # request cannot be replayed later against the receiver.
  def signature(timestamp, body)
    secret = @organization.alert_webhook_secret.to_s
    "v1=" + OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
  end

  private

  def perform(uri, request)
    destination = resolved_destination(uri)

    # Connect to the address that was validated, while keeping the hostname for
    # SNI and certificate verification. Without pinning, a host can resolve to a
    # public address during validation and a private one at connect time — the
    # gap DNS rebinding walks through.
    Net::HTTP.start(
      uri.host, uri.port,
      use_ssl: uri.scheme == "https",
      ipaddr: destination.address.to_s,
      open_timeout: TIMEOUT,
      read_timeout: TIMEOUT,
      verify_mode: OpenSSL::SSL::VERIFY_PEER
    ) { |conn| conn.request(request) }
  end

  def validated_uri(raw)
    resolved_destination(raw).uri
  end

  def resolved_destination(raw)
    OutboundHttpDestination.resolve!(raw.to_s, https_only: true)
  rescue OutboundHttpDestination::UnsafeDestination => e
    raise UnsafeDestination, "webhook URL #{e.message}"
  end

  def event_name(kind)
    case kind
    when "down"         then "service.down"
    when "tls_expiring" then "service.certificate_expiring"
    else                     "service.recovered"
    end
  end

  def payload(kind, service, error_message, downtime_started_at)
    {
      event: event_name(kind),
      occurred_at: Time.current.iso8601,
      organization: { name: @organization.name, slug: @organization.slug },
      service: {
        id: service.id,
        name: service.name,
        url: service.url,
        http_method: service.http_method,
        status: service.status,
        last_checked_at: service.last_checked_at&.iso8601,
        last_status_code: service.last_status_code,
        last_response_time_ms: service.last_response_time_ms,
        check_interval_seconds: service.check_interval_seconds
      },
      certificate: certificate_payload(service),
      error_message: error_message,
      downtime_started_at: downtime_started_at&.iso8601
    }.compact
  end

  def certificate_payload(service)
    return nil if service.tls_expires_at.blank?

    {
      expires_at: service.tls_expires_at.iso8601,
      days_remaining: service.tls_days_remaining,
      issuer: service.tls_issuer
    }
  end
end

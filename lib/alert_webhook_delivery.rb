require "net/http"
require "uri"
require "json"
require "ipaddr"
require "resolv"

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
  BLOCKED_RANGES = [
    IPAddr.new("0.0.0.0/8"),
    IPAddr.new("10.0.0.0/8"),
    IPAddr.new("100.64.0.0/10"),
    IPAddr.new("127.0.0.0/8"),
    IPAddr.new("169.254.0.0/16"),
    IPAddr.new("172.16.0.0/12"),
    IPAddr.new("192.168.0.0/16"),
    IPAddr.new("::1/128"),
    IPAddr.new("fc00::/7"),
    IPAddr.new("fe80::/10")
  ].freeze

  # Form-time validation. Deliberately does NO name resolution: a model
  # validation that performs DNS is slow, fails when DNS does, and would block
  # saving unrelated settings — including turning alerts off — whenever the
  # configured host happens to be unreachable. The authoritative check happens
  # at delivery, where the address is also pinned.
  #
  # Literal addresses are still rejected here, since that costs nothing.
  def self.validate_format!(raw)
    uri = URI.parse(raw.to_s)

    raise UnsafeDestination, "must use https" unless uri.is_a?(URI::HTTPS)
    raise UnsafeDestination, "must include a host" if uri.host.blank?

    host = uri.host.delete_prefix("[").delete_suffix("]")
    literal = (IPAddr.new(host) rescue nil)

    if literal && BLOCKED_RANGES.any? { |range| range.include?(literal) }
      raise UnsafeDestination, "must not point at a private or reserved address"
    end

    uri
  rescue URI::InvalidURIError
    raise UnsafeDestination, "is not a valid URL"
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
    request["X-StatusPulse-Event"] = kind == "down" ? "service.down" : "service.recovered"
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
    address = resolved_address(uri.host)

    # Connect to the address that was validated, while keeping the hostname for
    # SNI and certificate verification. Without pinning, a host can resolve to a
    # public address during validation and a private one at connect time — the
    # gap DNS rebinding walks through.
    Net::HTTP.start(
      uri.host, uri.port,
      use_ssl: uri.scheme == "https",
      ipaddr: address.to_s,
      open_timeout: TIMEOUT,
      read_timeout: TIMEOUT,
      verify_mode: OpenSSL::SSL::VERIFY_PEER
    ) { |conn| conn.request(request) }
  end

  def validated_uri(raw)
    uri = URI.parse(raw.to_s)

    unless uri.is_a?(URI::HTTPS)
      raise UnsafeDestination, "webhook URL must use https"
    end

    raise UnsafeDestination, "webhook URL has no host" if uri.host.blank?

    resolved_address(uri.host)
    uri
  rescue URI::InvalidURIError
    raise UnsafeDestination, "webhook URL is not a valid URL"
  end

  def resolved_address(host)
    # URI#host keeps the brackets on an IPv6 literal, which then fails to
    # resolve and gets blocked for the wrong reason. Strip them so a literal is
    # classified as the address it is.
    host = host.to_s.delete_prefix("[").delete_suffix("]")

    literal = (IPAddr.new(host) rescue nil)
    return guard_address(literal) if literal

    addresses = Resolv.getaddresses(host)
    raise UnsafeDestination, "webhook host does not resolve" if addresses.empty?

    address = addresses.map { |a| IPAddr.new(a) rescue nil }.compact.first
    raise UnsafeDestination, "webhook host does not resolve" if address.nil?

    guard_address(address)
  end

  def guard_address(address)
    if BLOCKED_RANGES.any? { |range| range.include?(address) }
      raise UnsafeDestination, "webhook host resolves to a private or reserved address"
    end

    address
  end

  def payload(kind, service, error_message, downtime_started_at)
    {
      event: kind == "down" ? "service.down" : "service.recovered",
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
      error_message: error_message,
      downtime_started_at: downtime_started_at&.iso8601
    }.compact
  end
end

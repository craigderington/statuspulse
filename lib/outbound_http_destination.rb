require "ipaddr"
require "resolv"
require "uri"

# Validates customer-controlled HTTP destinations and pins connections to an
# address that was checked. This is the security boundary between StatusPulse
# and private services reachable from its application network.
class OutboundHttpDestination
  class UnsafeDestination < StandardError; end

  BLOCKED_RANGES = %w[
    0.0.0.0/8
    10.0.0.0/8
    100.64.0.0/10
    127.0.0.0/8
    169.254.0.0/16
    172.16.0.0/12
    192.0.0.0/24
    192.0.2.0/24
    192.168.0.0/16
    198.18.0.0/15
    198.51.100.0/24
    203.0.113.0/24
    224.0.0.0/4
    240.0.0.0/4
    ::/128
    ::1/128
    ::ffff:0:0/96
    64:ff9b:1::/48
    100::/64
    2001:db8::/32
    fc00::/7
    fe80::/10
    ff00::/8
  ].map { |range| IPAddr.new(range) }.freeze

  Result = Data.define(:uri, :address)

  def self.validate_format!(raw, https_only: false)
    uri = parse(raw)
    allowed = https_only ? [ "https" ] : [ "http", "https" ]

    raise UnsafeDestination, "must use #{allowed.join(' or ')}" unless allowed.include?(uri.scheme&.downcase)
    raise UnsafeDestination, "must include a host" if uri.host.blank?
    raise UnsafeDestination, "must not include credentials" if uri.userinfo.present?

    literal = parse_address(uri.host)
    guard_address!(literal) if literal
    uri
  end

  def self.resolve!(raw, https_only: false, resolver: Resolv)
    uri = validate_format!(raw, https_only: https_only)
    host = normalized_host(uri.host)
    literal = parse_address(host)
    addresses = literal ? [ literal ] : resolver.getaddresses(host).filter_map { |value| parse_address(value) }

    raise UnsafeDestination, "host does not resolve" if addresses.empty?

    # Reject the whole answer if any address is unsafe. Selecting only the first
    # public result would leave failover and resolver-order changes dangerous.
    addresses.each { |address| guard_address!(address) }
    Result.new(uri:, address: addresses.first)
  end

  def self.parse(raw)
    URI.parse(raw.to_s)
  rescue URI::InvalidURIError
    raise UnsafeDestination, "is not a valid URL"
  end
  private_class_method :parse

  def self.normalized_host(host)
    host.to_s.delete_prefix("[").delete_suffix("]")
  end
  private_class_method :normalized_host

  def self.parse_address(host)
    IPAddr.new(normalized_host(host))
  rescue IPAddr::InvalidAddressError
    nil
  end
  private_class_method :parse_address

  def self.guard_address!(address)
    if BLOCKED_RANGES.any? { |range| range.include?(address) }
      raise UnsafeDestination, "must not point at a private or reserved address"
    end

    address
  end
  private_class_method :guard_address!
end

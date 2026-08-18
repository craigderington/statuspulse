require "test_helper"
require Rails.root.join("lib/outbound_http_destination")

class OutboundHttpDestinationTest < ActiveSupport::TestCase
  test "rejects private, loopback, metadata, reserved and IPv4-mapped destinations" do
    %w[
      http://127.0.0.1/
      http://10.0.0.1/
      http://169.254.169.254/latest/meta-data/
      http://192.168.1.1/
      http://198.51.100.2/
      http://[::1]/
      http://[::ffff:127.0.0.1]/
      http://[fc00::1]/
    ].each do |url|
      assert_raises(OutboundHttpDestination::UnsafeDestination, url) do
        OutboundHttpDestination.resolve!(url)
      end
    end
  end

  test "rejects credentials and non-http schemes" do
    assert_raises(OutboundHttpDestination::UnsafeDestination) do
      OutboundHttpDestination.validate_format!("https://user:pass@example.com/")
    end
    assert_raises(OutboundHttpDestination::UnsafeDestination) do
      OutboundHttpDestination.validate_format!("file:///etc/passwd")
    end
  end

  test "rejects an entire DNS answer when any address is unsafe" do
    resolver = Object.new
    resolver.define_singleton_method(:getaddresses) { |_host| [ "93.184.216.34", "127.0.0.1" ] }
    assert_raises(OutboundHttpDestination::UnsafeDestination) do
      OutboundHttpDestination.resolve!("https://mixed.example/health", resolver: resolver)
    end
  end

  test "returns a validated address for connection pinning" do
    resolver = Object.new
    resolver.define_singleton_method(:getaddresses) { |_host| [ "93.184.216.34" ] }
    result = OutboundHttpDestination.resolve!("https://public.example/health", resolver: resolver)

    assert_equal "public.example", result.uri.host
    assert_equal IPAddr.new("93.184.216.34"), result.address
  end
end

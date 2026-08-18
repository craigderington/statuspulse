require "test_helper"

class ServiceTest < ActiveSupport::TestCase
  setup do
    @organization = Organization.create!(name: "Service Model Org", slug: "service-model-org")
  end

  test "validates HTTP method inclusion" do
    service = @organization.services.new(name: "Test", url: "https://example.com", http_method: "INVALID")
    assert_not service.valid?
    assert_includes service.errors[:http_method], "is not included in the list"

    %w[GET POST PUT HEAD PATCH DELETE OPTIONS].each do |method|
      service.http_method = method
      assert service.valid?, "Expected #{method} to be valid"
    end
  end

  test "parses JSON headers correctly" do
    service = Service.new(headers: '{"Authorization": "Bearer 123", "User-Agent": "TestAgent"}')
    assert_equal({ "Authorization" => "Bearer 123", "User-Agent" => "TestAgent" }, service.parsed_headers)
  end

  test "parses multiline line-by-line headers correctly" do
    service = Service.new(headers: "Authorization: Bearer 456\nAccept: application/json")
    assert_equal({ "Authorization" => "Bearer 456", "Accept" => "application/json" }, service.parsed_headers)
  end

  test "performs check and records success log" do
    service = @organization.services.create!(
      name: "Example API",
      url: "https://example.com/api/health",
      http_method: "GET",
      expected_status_code: 200,
      status: "operational"
    )

    dummy_response = Net::HTTPSuccess.new("1.1", "200", "OK")
    dummy_response.instance_variable_set(:@read, true)
    dummy_response.define_singleton_method(:body) { "OK" }

    http = Object.new
    %i[use_ssl= open_timeout= read_timeout= verify_mode= ipaddr=].each do |writer|
      http.define_singleton_method(writer) { |_value| }
    end
    http.define_singleton_method(:use_ssl?) { true }
    http.define_singleton_method(:start) { @started = true }
    http.define_singleton_method(:started?) { @started }
    http.define_singleton_method(:request) { |_request| dummy_response }
    http.define_singleton_method(:peer_cert) { nil }
    http.define_singleton_method(:finish) { @started = false }

    destination = OutboundHttpDestination::Result.new(
      uri: URI("https://example.com/api/health"), address: IPAddr.new("93.184.216.34")
    )

    service.define_singleton_method(:resolved_destination) { destination }
    service.define_singleton_method(:build_http) { |_uri, _address| http }
    assert_difference "CheckLog.count", 1 do
      service.perform_check!
    end

    assert service.last_checked_at.present?
  end
end

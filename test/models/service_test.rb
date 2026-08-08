require "test_helper"

class ServiceTest < ActiveSupport::TestCase
  test "validates HTTP method inclusion" do
    service = Service.new(name: "Test", url: "https://example.com", http_method: "INVALID")
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
    service = Service.create!(
      name: "Example API",
      url: "https://example.com/api/health",
      http_method: "GET",
      expected_status_code: 200,
      status: "operational"
    )

    dummy_response = Net::HTTPSuccess.new("1.1", "200", "OK")
    dummy_response.instance_variable_set(:@read, true)
    dummy_response.stubs(:body).returns("OK") rescue nil

    Net::HTTP.any_instance.stubs(:request).returns(dummy_response) rescue nil

    assert_difference "CheckLog.count", 1 do
      service.perform_check!
    end

    assert service.last_checked_at.present?
  end
end

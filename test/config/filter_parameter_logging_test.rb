require "test_helper"

class FilterParameterLoggingTest < ActiveSupport::TestCase
  test "monitor credentials and authentication proofs are filtered" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter(
      "code" => "123456",
      "headers" => "Authorization: Bearer secret",
      "request_body" => "password=secret",
      "expected_body_match" => "private marker",
      "safe" => "visible"
    )

    assert_equal "visible", filtered["safe"]
    %w[code headers request_body expected_body_match].each do |key|
      assert_equal "[FILTERED]", filtered[key]
    end
  end
end

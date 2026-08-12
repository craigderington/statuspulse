require "test_helper"

class ServiceDueForCheckTest < ActiveSupport::TestCase
  def build_service(attrs = {})
    Service.new({
      name: "Core API",
      url: "https://example.test/health",
      http_method: "GET",
      expected_status_code: 200,
      timeout_seconds: 10,
      status: "operational",
      check_interval_seconds: 60
    }.merge(attrs))
  end

  test "a service that has never been checked is due immediately" do
    assert build_service(last_checked_at: nil).due_for_check?
  end

  test "a service checked longer ago than its interval is due" do
    service = build_service(check_interval_seconds: 60, last_checked_at: 90.seconds.ago)

    assert service.due_for_check?
  end

  test "a service checked within its interval is not due" do
    service = build_service(check_interval_seconds: 300, last_checked_at: 60.seconds.ago)

    assert_not service.due_for_check?
  end

  test "each service honours its own interval rather than a global one" do
    fast = build_service(check_interval_seconds: 30, last_checked_at: 45.seconds.ago)
    slow = build_service(check_interval_seconds: 600, last_checked_at: 45.seconds.ago)

    assert fast.due_for_check?
    assert_not slow.due_for_check?
  end

  test "seconds_until_next_check counts down and floors at zero" do
    service = build_service(check_interval_seconds: 300, last_checked_at: 60.seconds.ago)
    assert_in_delta 240, service.seconds_until_next_check, 2

    overdue = build_service(check_interval_seconds: 60, last_checked_at: 500.seconds.ago)
    assert_equal 0, overdue.seconds_until_next_check

    assert_equal 0, build_service(last_checked_at: nil).seconds_until_next_check
  end
end

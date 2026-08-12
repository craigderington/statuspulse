require "test_helper"

class ServicePauseTest < ActiveSupport::TestCase
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

  test "a service is not paused by default" do
    assert_not build_service.paused?
  end

  test "a paused service is never due for a check even when overdue" do
    service = build_service(last_checked_at: 1.hour.ago, paused_at: Time.current)

    assert_not service.due_for_check?
  end

  test "a paused service that has never been checked is still not due" do
    service = build_service(last_checked_at: nil, paused_at: Time.current)

    assert_not service.due_for_check?
  end

  test "resuming makes an overdue service due again" do
    service = build_service(last_checked_at: 1.hour.ago, paused_at: Time.current)
    assert_not service.due_for_check?

    service.paused_at = nil

    assert service.due_for_check?
  end

  test "a paused service reports no countdown" do
    service = build_service(last_checked_at: 10.seconds.ago, paused_at: Time.current)

    assert_equal 0, service.seconds_until_next_check
  end

  test "pausing preserves the last known status rather than resetting it" do
    org = Organization.create!(name: "Acme", slug: "acme-pause-test")
    service = build_service(organization: org, status: "degraded", last_checked_at: 2.minutes.ago)
    service.save!

    service.pause!

    assert service.reload.paused?
    assert_equal "degraded", service.status
  end

  test "resume clears the paused timestamp" do
    org = Organization.create!(name: "Acme", slug: "acme-resume-test")
    service = build_service(organization: org)
    service.save!
    service.pause!

    service.resume!

    assert_not service.reload.paused?
    assert_nil service.paused_at
  end

  test "scopes separate monitored services from paused ones" do
    org = Organization.create!(name: "Acme", slug: "acme-scope-test")
    live = build_service(organization: org, name: "Live")
    live.save!
    halted = build_service(organization: org, name: "Halted")
    halted.save!
    halted.pause!

    assert_includes Service.monitored, live
    assert_not_includes Service.monitored, halted
    assert_includes Service.paused, halted
    assert_not_includes Service.paused, live
  end
end

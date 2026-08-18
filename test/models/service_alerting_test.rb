require "test_helper"

# The trigger logic. Getting this wrong produces either alert fatigue or
# silence, and both end with people ignoring the product.
class ServiceAlertingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @org = Organization.create!(name: "Northwind", slug: "northwind-alerting")
    @org.users.create!(
      name: "Ops", email: "ops@northwind-alerting.test", role: "admin",
      password: "a-long-enough-password", password_confirmation: "a-long-enough-password"
    )
    @service = @org.services.create!(
      name: "Core API", url: "https://example.test/health", http_method: "GET",
      expected_status_code: 200, timeout_seconds: 10, status: "operational",
      check_interval_seconds: 60
    )
  end

  def fail!(message = "Expected HTTP 200, got 502")
    @service.evaluate_alerting!(false, message)
  end

  def succeed!
    @service.evaluate_alerting!(true)
  end

  test "a single failure does not alert" do
    assert_no_enqueued_jobs(only: ServiceAlertJob) { fail! }

    assert_equal 1, @service.reload.consecutive_failures
    assert_not @service.alerting?
  end

  test "the configured number of consecutive failures alerts once" do
    fail!
    assert_enqueued_with(job: ServiceAlertJob) { fail! }

    assert @service.reload.alerting?
    assert_equal Service::ALERT_AFTER_CONSECUTIVE_FAILURES, @service.consecutive_failures
  end

  test "a continuing outage does not alert again on every check" do
    fail!
    fail!
    @service.reload

    assert_no_enqueued_jobs(only: ServiceAlertJob) do
      6.times { fail! }
    end

    assert_equal Service::ALERT_AFTER_CONSECUTIVE_FAILURES + 6, @service.reload.consecutive_failures
  end

  test "an intermittent failure never reaches the threshold" do
    assert_no_enqueued_jobs(only: ServiceAlertJob) do
      4.times do
        fail!
        succeed!
      end
    end

    assert_equal 0, @service.reload.consecutive_failures
  end

  test "recovery alerts once and clears the alerting state" do
    fail!
    fail!
    @service.reload
    assert @service.alerting?

    assert_enqueued_with(job: ServiceAlertJob) { succeed! }

    assert_not @service.reload.alerting?
    assert_equal 0, @service.consecutive_failures
  end

  test "a success while not alerting sends nothing" do
    assert_no_enqueued_jobs(only: ServiceAlertJob) { succeed! }
  end

  test "recovery after a resolved outage can alert again on the next one" do
    fail!; fail!; succeed!
    @service.reload

    fail!
    assert_enqueued_with(job: ServiceAlertJob) { fail! }
  end

  test "a workspace with alerts disabled is never notified" do
    @org.update!(alerts_enabled: false)

    assert_no_enqueued_jobs(only: ServiceAlertJob) do
      fail!
      fail!
      fail!
    end

    assert_not @service.reload.alerting?,
      "alerting state must not be set when nothing was sent, or recovery would be missed too"
  end

  test "the database prevents orphaned services" do
    assert_raises(ActiveRecord::NotNullViolation) do
      @service.update_columns(organization_id: nil)
    end
  end

  test "the alert is recorded before dispatch so a delivery failure cannot re-alert" do
    fail!
    fail!

    assert_not_nil @service.reload.alerted_at,
      "alerted_at must be set independently of whether delivery succeeded"
  end
end

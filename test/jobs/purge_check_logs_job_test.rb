require "test_helper"

class PurgeCheckLogsJobTest < ActiveSupport::TestCase
  setup do
    @org = Organization.create!(name: "Northwind", slug: "northwind-purge")
    @service = @org.services.create!(
      name: "Core API", url: "https://example.test/health", http_method: "GET",
      expected_status_code: 200, timeout_seconds: 10, status: "operational",
      check_interval_seconds: 60
    )
  end

  def log_at(time, success: true)
    @service.check_logs.create!(
      status_code: success ? 200 : 500, response_time_ms: 120,
      success: success, created_at: time
    )
  end

  test "deletes logs older than the retention window" do
    old = log_at(CheckLog.retention_days.days.ago - 1.day)
    recent = log_at(1.day.ago)

    PurgeCheckLogsJob.perform_now

    assert_not CheckLog.exists?(old.id)
    assert CheckLog.exists?(recent.id)
  end

  test "keeps a log sitting just inside the window" do
    edge = log_at(CheckLog.retention_days.days.ago + 1.hour)

    PurgeCheckLogsJob.perform_now

    assert CheckLog.exists?(edge.id), "a log inside the window must survive"
  end

  test "returns how many it removed" do
    3.times { |i| log_at(CheckLog.retention_days.days.ago - (i + 1).days) }
    log_at(1.hour.ago)

    assert_equal 3, PurgeCheckLogsJob.perform_now
  end

  test "is safe to run when there is nothing to remove" do
    log_at(1.hour.ago)

    assert_equal 0, PurgeCheckLogsJob.perform_now
    # Scoped to this service: fixtures load unrelated check_logs.
    assert_equal 1, @service.check_logs.count
  end

  test "works across more rows than a single batch" do
    total = PurgeCheckLogsJob::BATCH_SIZE + 25
    cutoff = CheckLog.retention_days.days.ago - 1.day
    rows = Array.new(total) do
      { service_id: @service.id, status_code: 200, response_time_ms: 100,
        success: true, created_at: cutoff, updated_at: cutoff }
    end
    CheckLog.insert_all!(rows)

    assert_equal total, PurgeCheckLogsJob.perform_now
    assert_equal 0, @service.check_logs.count
  end

  test "purging does not touch another tenant's recent logs" do
    other_org = Organization.create!(name: "Meridian", slug: "meridian-purge")
    other = other_org.services.create!(
      name: "Other", url: "https://example.test/other", http_method: "GET",
      expected_status_code: 200, timeout_seconds: 10, status: "operational",
      check_interval_seconds: 60
    )
    kept = other.check_logs.create!(status_code: 200, response_time_ms: 90, success: true, created_at: 2.days.ago)
    log_at(CheckLog.retention_days.days.ago - 1.day)

    PurgeCheckLogsJob.perform_now

    assert CheckLog.exists?(kept.id)
  end

  test "the retention window is configurable" do
    previous = ENV["CHECK_LOG_RETENTION_DAYS"]
    ENV["CHECK_LOG_RETENTION_DAYS"] = "7"

    assert_equal 7, CheckLog.retention_days
    kept = log_at(3.days.ago)
    purged = log_at(10.days.ago)

    PurgeCheckLogsJob.perform_now

    assert CheckLog.exists?(kept.id)
    assert_not CheckLog.exists?(purged.id)
  ensure
    ENV["CHECK_LOG_RETENTION_DAYS"] = previous
  end
end

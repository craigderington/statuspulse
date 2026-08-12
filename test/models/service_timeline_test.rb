require "test_helper"

class ServiceTimelineTest < ActiveSupport::TestCase
  setup do
    @org = Organization.create!(name: "Acme", slug: "acme-timeline-test")
    @service = Service.create!(
      organization: @org,
      name: "Core API",
      url: "https://example.test/health",
      http_method: "GET",
      expected_status_code: 200,
      timeout_seconds: 10,
      status: "operational",
      check_interval_seconds: 60
    )
  end

  def log_check!(at:, success: true)
    @service.check_logs.create!(
      status_code: success ? 200 : 500,
      response_time_ms: 120,
      success: success,
      created_at: at
    )
  end

  test "a service with no checks has no oldest timestamp to label" do
    assert_nil @service.oldest_history_check_at
  end

  test "the label reflects the oldest real check, not the padded strip width" do
    log_check!(at: 20.minutes.ago)
    log_check!(at: 5.minutes.ago)

    # The strip still draws TIMELINE_BAR_COUNT bars, but only 2 are real.
    assert_equal Service::TIMELINE_BAR_COUNT, @service.history_bars.size
    assert_in_delta 20.minutes.ago, @service.oldest_history_check_at, 5
  end

  test "padding bars are blank so they cannot be mistaken for passing checks" do
    log_check!(at: 1.minute.ago)

    bars = @service.history_bars
    blanks = bars.count { |b| b[:success].nil? }

    assert_equal Service::TIMELINE_BAR_COUNT - 1, blanks
    assert_equal true, bars.last[:success]
  end

  test "the oldest timestamp is bounded by the strip, not the whole history" do
    # One check far outside the window, plus a full strip of recent ones.
    log_check!(at: 30.days.ago)
    (Service::TIMELINE_BAR_COUNT + 5).times { |i| log_check!(at: (i + 1).minutes.ago) }

    oldest = @service.oldest_history_check_at

    assert_operator oldest, :>, 1.day.ago,
      "must not report a check that has already scrolled off the strip"
  end
end

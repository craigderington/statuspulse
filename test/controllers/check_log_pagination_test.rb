require "test_helper"

class CheckLogPaginationTest < ActionDispatch::IntegrationTest
  PER_PAGE = ServicesController::CHECKS_PER_PAGE

  setup do
    @org = Organization.create!(name: "Northwind", slug: "northwind-checks")
    @user = @org.users.create!(
      name: "Ops", email: "ops@northwind-checks.test", role: "admin",
      password: "a-long-enough-password", password_confirmation: "a-long-enough-password"
    )
    @service = @org.services.create!(
      name: "Core API", url: "https://example.test/health", http_method: "GET",
      expected_status_code: 200, timeout_seconds: 10, status: "operational",
      check_interval_seconds: 60
    )
    post login_url, params: { email: @user.email, password: "a-long-enough-password" }
  end

  def log_checks!(count)
    count.times do |i|
      @service.check_logs.create!(
        status_code: 200, response_time_ms: 100 + i, success: true,
        created_at: i.minutes.ago
      )
    end
  end

  test "a service with no checks renders without a pager" do
    get service_url(@service)

    assert_response :success
    assert_select ".pager", count: 0
  end

  test "fewer checks than a page shows the total but no page controls" do
    log_checks!(3)

    get service_url(@service)

    assert_select ".pager__count", /1–3 of 3 checks/
    assert_select ".pager__controls", count: 0
  end

  test "the first page shows the newest checks and offers older ones" do
    log_checks!(PER_PAGE + 10)

    get service_url(@service)

    assert_select ".pager__count", /1–#{PER_PAGE} of #{PER_PAGE + 10} checks/
    assert_select "a[rel=next]"
    assert_select "a[rel=prev]", count: 0
  end

  test "the last page shows the remainder and offers newer ones" do
    log_checks!(PER_PAGE + 10)

    get service_url(@service, page: 2)

    assert_select ".pager__count", /#{PER_PAGE + 1}–#{PER_PAGE + 10} of #{PER_PAGE + 10} checks/
    assert_select "a[rel=prev]"
    assert_select "a[rel=next]", count: 0
  end

  test "a page beyond the end clamps to the last page rather than erroring" do
    log_checks!(PER_PAGE + 10)

    get service_url(@service, page: 9_999)

    assert_response :success
    assert_select ".pager__position", /Page 2 of 2/
  end

  test "a nonsense page parameter falls back to the first page" do
    log_checks!(PER_PAGE + 10)

    get service_url(@service, page: "not-a-number")

    assert_response :success
    assert_select ".pager__count", /1–#{PER_PAGE} of/
  end

  test "older checks are actually reachable rather than silently truncated" do
    log_checks!(PER_PAGE + 1)
    oldest = @service.check_logs.order(:created_at).first

    get service_url(@service)
    assert_select "td", text: /#{oldest.response_time_ms} ms/, count: 0

    get service_url(@service, page: 2)
    assert_select "td", text: /#{oldest.response_time_ms} ms/
  end

  test "pagination stays inside the tenant" do
    other_org = Organization.create!(name: "Meridian", slug: "meridian-checks")
    other_service = other_org.services.create!(
      name: "Other API", url: "https://example.test/other", http_method: "GET",
      expected_status_code: 200, timeout_seconds: 10, status: "operational",
      check_interval_seconds: 60
    )

    get service_url(other_service)

    assert_response :not_found
  end
end

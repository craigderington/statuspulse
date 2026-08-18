require "test_helper"

class ReportsPeriodTest < ActionDispatch::IntegrationTest
  PASSWORD = "a-long-enough-password".freeze

  setup do
    @org = Organization.create!(name: "Northwind", slug: "northwind-reports")
    @user = @org.users.create!(
      name: "Ops", email: "ops@northwind-reports.test", role: "admin",
      password: PASSWORD, password_confirmation: PASSWORD
    )
    post login_url, params: { email: @user.email, password: PASSWORD }
  end

  test "a window beyond retention is clamped, and the page says so" do
    get reports_url(days: 3650)

    assert_response :success
    assert_select "[data-period-clamped]", /last #{CheckLog.retention_days} days/,
      "reporting over purged data would overstate uptime, so the truncation must be visible"
  end

  test "a window inside retention is honoured silently" do
    get reports_url(days: 7)

    assert_response :success
    assert_select "[data-period-clamped]", count: 0
    assert_select "nav[aria-label='Reporting period'] a", count: 3
    assert_select "a[aria-current='page'][href=?]", reports_path(days: 7), text: "7 days"
  end

  test "the default period is unchanged and unclamped" do
    get reports_url

    assert_response :success
    assert_select "[data-period-clamped]", count: 0
  end

  test "a nonsense period does not blow up" do
    get reports_url(days: "not-a-number")

    assert_response :success
  end
end

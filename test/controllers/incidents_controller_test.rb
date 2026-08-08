require "test_helper"

class IncidentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @org = Organization.create!(name: "Incident Test Org", slug: "incident-test-org")
    @user = User.create!(name: "Incident Admin", email: "admin@incidenttest.com", password: "password123", password_confirmation: "password123", organization: @org)
    @incident = Incident.create!(
      title: "Test Outage",
      description: "Database latency issue",
      severity: "degraded",
      status: "investigating",
      organization: @org
    )
    post login_url, params: { email: @user.email, password: "password123" }
  end

  test "should get index" do
    get incidents_url
    assert_response :success
  end

  test "should get new" do
    get new_incident_url
    assert_response :success
  end

  test "should get show" do
    get incident_url(@incident)
    assert_response :success
  end

  test "should get edit" do
    get edit_incident_url(@incident)
    assert_response :success
  end
end

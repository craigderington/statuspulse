require "test_helper"

class IncidentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @org = Organization.create!(name: "Incident Test Org", slug: "incident-test-org")
    @user = User.create!(name: "Incident Admin", email: "admin@incidenttest.com", password: "password123", password_confirmation: "password123", organization: @org, role: "admin")
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

  test "index and show do not expose another workspace incidents" do
    other = Organization.create!(name: "Other Incident Org", slug: "other-incident-org")
    foreign = other.incidents.create!(title: "Secret outage", description: "Private",
      severity: "major_outage", status: "investigating")

    get incidents_url
    assert_response :success
    assert_no_match(/Secret outage/, response.body)

    get incident_url(foreign)
    assert_response :not_found
  end

  test "cannot attach another workspace service" do
    foreign_org = Organization.create!(name: "Foreign Services", slug: "foreign-services")
    foreign_service = foreign_org.services.create!(name: "Foreign API", url: "https://example.com",
      http_method: "GET", expected_status_code: 200, status: "operational")

    assert_no_difference "Incident.count" do
      post incidents_url, params: {
        incident: { title: "Cross tenant", description: "No", severity: "degraded", status: "investigating" },
        service_ids: [ foreign_service.id ]
      }
    end
    assert_response :not_found
  end

  test "member can view but cannot mutate incidents or post updates" do
    delete logout_url
    member = @org.users.create!(name: "Member", email: "member@incidenttest.com",
      password: "password123", password_confirmation: "password123", role: "member")
    post login_url, params: { email: member.email, password: "password123" }

    get incident_url(@incident)
    assert_response :success

    assert_no_difference "Incident.count" do
      post incidents_url, params: { incident: { title: "Forbidden", severity: "degraded", status: "investigating" } }
    end
    assert_redirected_to dashboard_path

    assert_no_difference "IncidentUpdate.count" do
      post incident_incident_updates_url(@incident), params: { incident_update: { body: "Forbidden", status: "resolved" } }
    end
    assert_redirected_to dashboard_path
  end
end

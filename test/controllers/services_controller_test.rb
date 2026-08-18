require "test_helper"

class ServicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @org = Organization.create!(name: "Service Test Org", slug: "service-test-org")
    @user = User.create!(name: "Admin User", email: "admin@servicetest.com", password: "password123", password_confirmation: "password123", organization: @org, role: "admin")
    @service = Service.create!(
      name: "Test API",
      url: "https://httpbin.org/get",
      http_method: "GET",
      expected_status_code: 200,
      status: "operational",
      organization: @org
    )
    post login_url, params: { email: @user.email, password: "password123" }
  end

  test "should get index" do
    get services_url
    assert_response :success
  end

  test "should get new" do
    get new_service_url
    assert_response :success
  end

  test "should get show" do
    get service_url(@service)
    assert_response :success
  end

  test "should get edit" do
    get edit_service_url(@service)
    assert_response :success
  end

  test "member can view but cannot mutate services or trigger requests" do
    delete logout_url
    member = @org.users.create!(name: "Member", email: "member@servicetest.com",
      password: "password123", password_confirmation: "password123", role: "member")
    post login_url, params: { email: member.email, password: "password123" }

    get service_url(@service)
    assert_response :success

    post check_now_service_url(@service)
    assert_redirected_to dashboard_path

    assert_no_difference "Service.count" do
      post services_url, params: { service: { name: "Forbidden", url: "https://example.com" } }
    end
    assert_redirected_to dashboard_path
  end

  test "cannot access another workspace service" do
    other = Organization.create!(name: "Other Service Org", slug: "other-service-org")
    foreign = other.services.create!(name: "Private API", url: "https://example.com",
      http_method: "GET", expected_status_code: 200, status: "operational")

    get service_url(foreign)
    assert_response :not_found
    patch service_url(foreign), params: { service: { name: "Stolen" } }
    assert_response :not_found
  end
end

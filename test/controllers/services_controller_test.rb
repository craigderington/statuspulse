require "test_helper"

class ServicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @org = Organization.create!(name: "Service Test Org", slug: "service-test-org")
    @user = User.create!(name: "Admin User", email: "admin@servicetest.com", password: "password123", password_confirmation: "password123", organization: @org)
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
end

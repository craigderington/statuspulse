require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @org = Organization.create!(name: "Acme Test", slug: "acme-test")
    @user = User.create!(name: "Tester", email: "tester@example.com", password: "password123", password_confirmation: "password123", organization: @org)
  end

  test "should get index when logged in" do
    post login_url, params: { email: @user.email, password: "password123" }
    get root_url
    assert_response :success
  end
end

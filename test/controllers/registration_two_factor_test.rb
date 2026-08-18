require "test_helper"

class RegistrationTwoFactorTest < ActionDispatch::IntegrationTest
  test "mandatory two-factor signup is pending until enrolment completes" do
    with_two_factor_required do
      post signup_url, params: {
        organization_name: "New Secure Org",
        user: { name: "New Admin", email: "new-admin@example.test",
                password: "a-long-enough-password", password_confirmation: "a-long-enough-password" }
      }

      user = User.find_by!(email: "new-admin@example.test")
      assert_redirected_to two_factor_setup_path
      assert_nil session[:user_id]
      assert_equal user.id, session[:pending_user_id]

      get dashboard_url
      assert_redirected_to two_factor_setup_path
    end
  end
end

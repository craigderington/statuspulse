require "test_helper"

# Attacks that start from a stolen password against an account that already has
# a second factor. Each of these must fail.
class TwoFactorBypassTest < ActionDispatch::IntegrationTest
  PASSWORD = "a-long-enough-password".freeze

  setup do
    @org = Organization.create!(name: "Northwind", slug: "northwind-bypass")
    @victim = @org.users.create!(
      name: "Victim", email: "victim@northwind-bypass.test", role: "admin",
      password: PASSWORD, password_confirmation: PASSWORD
    )
    enrol_totp!(@victim)
    @secret = @victim.reload.totp_secret
  end

  # The attacker knows the password and nothing else.
  def steal_password!
    post login_url, params: { email: @victim.email, password: PASSWORD }
  end

  test "the enrolment page does not disclose an existing secret to a password-only attacker" do
    steal_password!

    get two_factor_setup_url

    assert_response :redirect
    assert_redirected_to two_factor_path,
      "an enrolled account must be challenged, not offered enrolment again"

    follow_redirect!
    assert_not_includes response.body, @secret,
      "the existing TOTP secret must never be rendered on the strength of a password alone"
  end

  test "an attacker cannot re-enrol an account that already has a second factor" do
    steal_password!

    get two_factor_setup_url
    post two_factor_setup_url, params: { code: "000000" }

    assert_nil session[:user_id]
    assert_equal @secret, @victim.reload.totp_secret,
      "the victim's secret must not be replaced"
  end

  test "acknowledging recovery codes cannot sign in a session that never enrolled" do
    steal_password!

    post confirm_two_factor_recovery_codes_url

    assert_nil session[:user_id],
      "posting to the recovery-codes acknowledgement must not complete authentication"
  end

  test "the recovery codes screen shows nothing to a password-only attacker" do
    steal_password!

    get two_factor_recovery_codes_url

    assert_nil session[:user_id]
    @victim.recovery_codes.each do |code|
      assert_not_includes response.body, code.code_digest
    end
  end

  test "the dashboard stays closed throughout" do
    steal_password!

    get two_factor_setup_url
    post confirm_two_factor_recovery_codes_url
    get dashboard_url

    assert_nil session[:user_id]
    assert_response :redirect
    assert_no_match(/Services Telemetry/, response.body)
  end
end

require "test_helper"

class SecurityControllerTest < ActionDispatch::IntegrationTest
  PASSWORD = "a-long-enough-password".freeze

  setup do
    @org = Organization.create!(name: "Northwind", slug: "northwind-security")
    @member = @org.users.create!(
      name: "Member", email: "member@northwind-security.test", role: "member",
      password: PASSWORD, password_confirmation: PASSWORD
    )
  end

  def sign_in_as(user)
    post login_url, params: { email: user.email, password: PASSWORD }
  end

  test "requires a signed-in user" do
    get security_url

    assert_redirected_to login_path
  end

  test "a member can reach their own security page" do
    sign_in_as(@member)

    get security_url

    assert_response :success
    # A member, not an admin — enrolment must not be gated behind workspace settings.
    assert_select "a[href=?]", two_factor_setup_path
  end

  test "shows two-factor as off with a route to enable it" do
    sign_in_as(@member)

    get security_url

    assert_select ".badge-degraded", /off/i
  end

  test "shows two-factor as on once enrolled" do
    enrol_totp!(@member)
    travel 31.seconds
    sign_in_as(@member)
    post two_factor_url, params: { code: @member.reload.totp.now }

    get security_url

    assert_select ".badge-operational", /on/i
  end

  test "regenerating recovery codes requires a valid authenticator code" do
    enrol_totp!(@member)
    original = RecoveryCode.regenerate_for!(@member)
    travel 31.seconds
    sign_in_as(@member)
    post two_factor_url, params: { code: @member.reload.totp.now }

    post regenerate_recovery_codes_url, params: { code: "000000" }

    assert_redirected_to security_path
    assert_match(/not valid/i, flash[:alert])
    # The old codes must still work.
    assert RecoveryCode.consume!(@member, original.first)
  end

  test "a valid code issues a new set and invalidates the old one" do
    enrol_totp!(@member)
    original = RecoveryCode.regenerate_for!(@member)
    travel 31.seconds
    sign_in_as(@member)
    post two_factor_url, params: { code: @member.reload.totp.now }

    travel 31.seconds
    post regenerate_recovery_codes_url, params: { code: @member.reload.totp.now }

    assert_redirected_to security_path
    assert_not RecoveryCode.consume!(@member, original.first),
      "codes from the previous set must stop working"
    assert_equal RecoveryCode::BATCH_SIZE, @member.recovery_codes.unused.count
  end

  test "new codes are displayed once and not again on reload" do
    enrol_totp!(@member)
    travel 31.seconds
    sign_in_as(@member)
    post two_factor_url, params: { code: @member.reload.totp.now }

    travel 31.seconds
    post regenerate_recovery_codes_url, params: { code: @member.reload.totp.now }

    follow_redirect!
    assert_select ".codes__code", count: RecoveryCode::BATCH_SIZE

    get security_url
    assert_select ".codes__code", count: 0, message: "codes must not persist across a reload"
  end

  test "an unenrolled user is sent to setup rather than regenerating nothing" do
    sign_in_as(@member)

    post regenerate_recovery_codes_url, params: { code: "000000" }

    assert_redirected_to two_factor_setup_path
  end
end

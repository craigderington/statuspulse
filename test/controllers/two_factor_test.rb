require "test_helper"

class TwoFactorTest < ActionDispatch::IntegrationTest
  PASSWORD = "a-long-enough-password".freeze

  setup do
    @org = Organization.create!(name: "Northwind", slug: "northwind-2fa")
    @user = @org.users.create!(
      name: "Ops", email: "ops@northwind-2fa.test", role: "admin",
      password: PASSWORD, password_confirmation: PASSWORD
    )
  end

  def submit_password
    post login_url, params: { email: @user.email, password: PASSWORD }
  end

  # ---- the core guarantee -------------------------------------------------

  test "a correct password alone does not sign you in" do
    enrol_totp!(@user)

    submit_password

    assert_redirected_to two_factor_path
    assert_nil session[:user_id], "password alone must not authenticate"

    # And the app itself is still closed.
    get dashboard_url
    assert_redirected_to two_factor_path
  end

  test "a valid code completes sign-in" do
    enrol_totp!(@user)

    # Enrolment consumed the current timestep by design, so cross into the next
    # one — which is what happens in reality between enrolling and signing in.
    travel 31.seconds

    submit_password
    post two_factor_url, params: { code: @user.reload.totp.now }

    assert_redirected_to dashboard_path
    assert_equal @user.id, session[:user_id]
  end

  test "a wrong code does not sign you in" do
    enrol_totp!(@user)
    submit_password

    post two_factor_url, params: { code: "000000" }

    assert_response :unprocessable_entity
    assert_nil session[:user_id]
  end

  test "a code cannot be replayed" do
    enrol_totp!(@user)
    travel 31.seconds
    code = @user.reload.totp.now

    submit_password
    post two_factor_url, params: { code: code }
    assert_equal @user.id, session[:user_id]

    delete logout_url
    submit_password
    post two_factor_url, params: { code: code }

    assert_response :unprocessable_entity
    assert_nil session[:user_id], "an observed code must not work twice"
  end

  test "the challenge cannot be reached without proving a password first" do
    enrol_totp!(@user)

    post two_factor_url, params: { code: @user.totp.now }

    assert_redirected_to login_path
    assert_nil session[:user_id]
  end

  test "a pending sign-in expires rather than waiting indefinitely" do
    enrol_totp!(@user)
    travel 31.seconds
    submit_password

    travel(Authentication::PENDING_WINDOW + 1.minute) do
      post two_factor_url, params: { code: @user.reload.totp.now }

      assert_redirected_to login_path
      assert_nil session[:user_id]
    end
  end

  # ---- recovery codes -----------------------------------------------------

  test "a recovery code signs you in and is then spent" do
    enrol_totp!(@user)
    codes = RecoveryCode.regenerate_for!(@user)

    submit_password
    post two_factor_url, params: { code: codes.first }
    assert_equal @user.id, session[:user_id]

    delete logout_url
    submit_password
    post two_factor_url, params: { code: codes.first }

    assert_response :unprocessable_entity
    assert_nil session[:user_id], "a recovery code must work only once"
  end

  test "another user's recovery code does not work" do
    enrol_totp!(@user)
    other = @org.users.create!(
      name: "Other", email: "other@northwind-2fa.test", role: "member",
      password: PASSWORD, password_confirmation: PASSWORD
    )
    other_codes = RecoveryCode.regenerate_for!(other)

    submit_password
    post two_factor_url, params: { code: other_codes.first }

    assert_response :unprocessable_entity
    assert_nil session[:user_id]
  end

  # ---- enrolment ----------------------------------------------------------

  test "an unenrolled user is sent to setup and cannot skip it" do
    with_two_factor_required do
      submit_password

      assert_redirected_to two_factor_setup_path
      assert_nil session[:user_id]

      get dashboard_url
      assert_redirected_to two_factor_setup_path
    end
  end

  test "enrolment is only completed by proving a code" do
    with_two_factor_required do
      submit_password
      get two_factor_setup_url
      assert_response :success

      # A secret is issued, but nothing is enabled yet.
      assert @user.reload.totp_secret.present?
      assert_not @user.totp_enabled?

      post two_factor_setup_url, params: { code: "000000" }
      assert_response :unprocessable_entity
      assert_not @user.reload.totp_enabled?
      assert_nil session[:user_id]

      post two_factor_setup_url, params: { code: @user.reload.totp.now }
      assert_redirected_to two_factor_recovery_codes_path
      assert @user.reload.totp_enabled?
    end
  end

  test "recovery codes are shown once and sign-in completes on acknowledgement" do
    with_two_factor_required do
      submit_password
      get two_factor_setup_url
      post two_factor_setup_url, params: { code: @user.reload.totp.now }

      get two_factor_recovery_codes_url
      assert_response :success
      assert_equal RecoveryCode::BATCH_SIZE, @user.recovery_codes.count
      assert_nil session[:user_id], "still not signed in until acknowledged"

      post confirm_two_factor_recovery_codes_url
      assert_equal @user.id, session[:user_id]

      # Revisiting must not re-display them.
      get two_factor_recovery_codes_url
      assert_redirected_to dashboard_path
    end
  end

  test "only digests of recovery codes are stored" do
    codes = RecoveryCode.regenerate_for!(@user)

    stored = RecoveryCode.where(user: @user).pluck(:code_digest)

    codes.each do |plaintext|
      assert_not_includes stored, plaintext
      assert_not_includes stored, RecoveryCode.normalize(plaintext)
    end
  end

  test "the totp secret is not stored in plain text" do
    enrol_totp!(@user)
    raw = ActiveRecord::Base.connection.select_value(
      "SELECT totp_secret FROM users WHERE id = #{@user.id}"
    )

    assert_not_includes raw.to_s, @user.reload.totp_secret
  end

  # ---- throttling ---------------------------------------------------------

  test "verification attempts are throttled" do
    enrol_totp!(@user)
    submit_password

    11.times { post two_factor_url, params: { code: "000000" } }

    assert_redirected_to login_path
    assert_match(/too many verification attempts/i, flash[:alert])
    assert_nil session[:user_id]
  end
end

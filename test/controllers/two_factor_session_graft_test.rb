require "test_helper"

# A session that holds BOTH a pending user and a signed-in user is the
# precondition for grafting one identity's proof onto another's sign-in.
class TwoFactorSessionGraftTest < ActionDispatch::IntegrationTest
  PASSWORD = "a-long-enough-password".freeze

  setup do
    @org = Organization.create!(name: "Victim Co", slug: "victim-co-graft")
    @victim = @org.users.create!(
      name: "Victim", email: "victim@graft.test", role: "admin",
      password: PASSWORD, password_confirmation: PASSWORD
    )
    enrol_totp!(@victim)
    travel 31.seconds
  end

  test "recovery codes minted by one account cannot authenticate another" do
    # 1. attacker submits the victim's stolen password
    post login_url, params: { email: @victim.email, password: PASSWORD }
    assert_nil session[:user_id], "password alone must not authenticate"

    # 2. in the SAME cookie jar, sign up a throwaway account
    post signup_url, params: {
      organization_name: "Attacker Co",
      user: { name: "Attacker", email: "attacker@graft.test",
              password: PASSWORD, password_confirmation: PASSWORD }
    }
    attacker = User.find_by(email: "attacker@graft.test")
    assert_not_nil attacker

    # 3. the attacker controls this account, so they can enrol it
    enrol_totp!(attacker)
    travel 31.seconds

    # 4. mint recovery codes using the ATTACKER's own valid code
    post regenerate_recovery_codes_url, params: { code: attacker.reload.totp.now }

    # 5. acknowledge them
    post confirm_two_factor_recovery_codes_url

    assert_not_equal @victim.id, session[:user_id],
      "a session must never be promoted to a user whose second factor was never supplied"
  end

  test "signing up rotates the session and clears any pending sign-in" do
    post login_url, params: { email: @victim.email, password: PASSWORD }

    post signup_url, params: {
      organization_name: "Attacker Co",
      user: { name: "Attacker", email: "attacker2@graft.test",
              password: PASSWORD, password_confirmation: PASSWORD }
    }

    assert_nil session[:pending_user_id],
      "a new identity must not inherit a pending sign-in for a different account"
  end
end

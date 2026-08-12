require "test_helper"

class RateLimitingTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
    @org = Organization.create!(name: "Acme", slug: "acme-rate-limit-test")
    @user = @org.users.create!(
      name: "Ops",
      email: "ops@statuspulse.test",
      password: "correct horse battery staple",
      password_confirmation: "correct horse battery staple",
      role: "admin"
    )
  end

  teardown { Rails.cache.clear }

  test "repeated failed sign-ins for one account are throttled" do
    6.times { post login_path, params: { email: @user.email, password: "wrong" } }

    assert_redirected_to login_path
    assert_match(/too many sign-in attempts for that account/i, flash[:alert])
  end

  test "the login throttle is keyed on email, so another account is unaffected" do
    5.times { post login_path, params: { email: @user.email, password: "wrong" } }

    post login_path, params: { email: "someone-else@statuspulse.test", password: "wrong" }

    # Rejected on credentials, not throttled.
    assert_response :unprocessable_entity
  end

  test "a throttled account cannot be signed into even with the correct password" do
    6.times { post login_path, params: { email: @user.email, password: "wrong" } }

    post login_path, params: { email: @user.email, password: "correct horse battery staple" }

    assert_redirected_to login_path
    assert_nil session[:user_id], "throttle must block before authentication"
  end

  test "email keying is normalised so case and whitespace cannot dodge the limit" do
    5.times { post login_path, params: { email: @user.email, password: "wrong" } }

    post login_path, params: { email: "  OPS@StatusPulse.TEST  ", password: "wrong" }

    assert_redirected_to login_path
    assert_match(/too many sign-in attempts/i, flash[:alert])
  end

  test "repeated sign-ups from one address are throttled" do
    6.times do |i|
      post signup_path, params: {
        organization_name: "Spam #{i}",
        user: {
          name: "Spam #{i}",
          email: "spam#{i}@statuspulse.test",
          password: "a-long-enough-password",
          password_confirmation: "a-long-enough-password"
        }
      }
    end

    assert_redirected_to signup_path
    assert_match(/too many sign-up attempts/i, flash[:alert])
  end

  test "the signup throttle stops organizations being created" do
    before_count = Organization.count

    10.times do |i|
      post signup_path, params: {
        organization_name: "Flood #{i}",
        user: {
          name: "Flood #{i}",
          email: "flood#{i}@statuspulse.test",
          password: "a-long-enough-password",
          password_confirmation: "a-long-enough-password"
        }
      }
    end

    assert_operator Organization.count - before_count, :<=, 5,
      "throttle must cap organization creation, not merely change the response"
  end
end

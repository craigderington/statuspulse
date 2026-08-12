# The sign-in challenge: proves possession of the authenticator, or burns a
# recovery code.
class TwoFactorController < ApplicationController
  layout "auth"

  # Six digits is a million combinations. Unthrottled, that is reachable; at ten
  # attempts a minute it is not. Keyed on the pending user rather than the IP so
  # the limit follows the account under attack.
  rate_limit to: 10, within: 1.minute,
             by: -> { "2fa:#{session[:pending_user_id]}" },
             with: -> { redirect_to login_path, alert: "Too many verification attempts. Please sign in again." },
             only: :create

  before_action :require_pending_user

  def new
  end

  def create
    if @user.verify_totp(params[:code])
      return sign_in!("Welcome back, #{@user.name}!")
    end

    # Recovery codes are accepted at the same prompt: someone who has lost their
    # phone should not have to find a different page to get in.
    if RecoveryCode.consume!(@user, params[:code])
      remaining = @user.recovery_codes.unused.count
      return sign_in!("Signed in with a recovery code. #{remaining} #{'code'.pluralize(remaining)} remaining.")
    end

    flash.now[:alert] = "That code was not valid. Codes change every 30 seconds — check your authenticator for the current one."
    render :new, status: :unprocessable_entity
  end

  private

  def sign_in!(message)
    complete_authentication(@user)
    redirect_to dashboard_path, notice: message
  end

  def require_pending_user
    @user = pending_user

    return redirect_to login_path, alert: "Your sign-in timed out. Please start again." if @user.nil?
    # An account without a second factor has nothing to challenge; send it to
    # enrolment rather than showing an unanswerable prompt.
    redirect_to two_factor_setup_path unless @user.totp_enabled?
  end
end

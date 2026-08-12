# Personal account security. Distinct from workspace settings, which are
# org-scoped and admin-only: two-factor authentication belongs to the person,
# and a member must be able to manage their own.
class SecurityController < ApplicationController
  # Minting a new set of recovery codes invalidates the old ones, so it is
  # treated as a sensitive action and throttled accordingly.
  rate_limit to: 5, within: 1.minute,
             by: -> { "recovery-regen:#{session[:user_id]}" },
             with: -> { redirect_to security_path, alert: "Too many attempts. Please wait a minute." },
             only: :regenerate_recovery_codes

  def show
    @user = Current.user
    @unused_recovery_codes = @user.recovery_codes.unused.count
    @fresh_codes = fresh_recovery_codes_for(@user)
    discard_fresh_recovery_codes
  end

  # Requires a current code. A hijacked session should not be able to mint
  # itself a fresh set of bypass codes without proving possession of the
  # authenticator.
  def regenerate_recovery_codes
    @user = Current.user

    unless @user.totp_enabled?
      return redirect_to two_factor_setup_path
    end

    unless @user.verify_totp(params[:code])
      return redirect_to security_path,
        alert: "That code was not valid, so your recovery codes are unchanged."
    end

    store_fresh_recovery_codes(@user, RecoveryCode.regenerate_for!(@user))
    redirect_to security_path,
      notice: "New recovery codes generated. Your previous codes no longer work."
  end
end

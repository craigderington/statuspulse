class SessionsController < ApplicationController
  # Keyed on the submitted email, not the IP: credential stuffing against a
  # single account is trivially distributed across addresses, and an IP-only
  # limit would never see it.
  rate_limit to: 5, within: 1.minute,
             by: -> { params[:email].to_s.downcase.strip },
             with: -> { redirect_to login_path, alert: "Too many sign-in attempts for that account. Please wait a minute and try again." },
             only: :create

  # Wider per-IP cap to catch spraying: many accounts, few attempts each, which
  # slips under the per-email limit above. Deliberately loose so a shared office
  # NAT is not locked out by ordinary use.
  rate_limit to: 20, within: 1.minute,
             with: -> { redirect_to login_path, alert: "Too many sign-in attempts from this network. Please wait a minute and try again." },
             only: :create

  def new
  end

  def create
    user = User.find_by(email: params[:email]&.downcase&.strip)

    unless user&.authenticate(params[:password])
      flash.now[:alert] = "Invalid email or password."
      return render :new, status: :unprocessable_entity
    end

    # The password is proved but the session is not yet authenticated. Which
    # step comes next depends on whether this account has a second factor.
    begin_pending_authentication(user)

    if user.totp_enabled?
      redirect_to two_factor_path
    elsif two_factor_required?
      redirect_to two_factor_setup_path, notice: "One more step: set up two-factor authentication to continue."
    else
      complete_authentication(user)
      redirect_to dashboard_path, notice: "Welcome back, #{user.name}!"
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "Signed out successfully."
  end
end

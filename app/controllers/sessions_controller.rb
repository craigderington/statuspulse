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
    if user && user.authenticate(params[:password])
      session[:user_id] = user.id
      redirect_to root_path, notice: "Welcome back, #{user.name}!"
    else
      flash.now[:alert] = "Invalid email or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    session[:user_id] = nil
    redirect_to login_path, notice: "Signed out successfully."
  end
end

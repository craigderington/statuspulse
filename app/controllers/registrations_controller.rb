class RegistrationsController < ApplicationController
  # Per-IP: every signup creates an Organization and a User, so an unthrottled
  # endpoint is a free way to fill the database. There is no useful per-account
  # key here — the account does not exist yet.
  rate_limit to: 5, within: 10.minutes,
             with: -> { redirect_to signup_path, alert: "Too many sign-up attempts. Please wait a few minutes and try again." },
             only: :create

  def new
    @user = User.new
    @organization_name = ""
  end

  def create
    org_name = params[:organization_name].presence || "My Organization"
    organization = Organization.create!(name: org_name)

    @user = organization.users.new(user_params)
    @user.role = "admin"

    if @user.save
      session[:user_id] = @user.id
      redirect_to dashboard_path, notice: "Account created! Welcome to StatusPulse."
    else
      organization.destroy rescue nil
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation)
  end
end

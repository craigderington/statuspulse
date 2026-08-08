class RegistrationsController < ApplicationController
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
      redirect_to root_path, notice: "Account created! Welcome to StatusPulse."
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

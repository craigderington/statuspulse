class SessionsController < ApplicationController
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

class ApplicationController < ActionController::Base
  before_action :set_current_context
  before_action :require_login

  private

  def set_current_context
    if session[:user_id]
      user = User.find_by(id: session[:user_id])
      if user
        Current.user = user
        Current.organization = user.organization
      end
    end

    # Fallback to first organization for unauthenticated / public access if needed
    Current.organization ||= Organization.first
  end

  def require_login
    return if Current.user.present? || public_action?

    redirect_to login_path, alert: "Please sign in to access StatusPulse dashboard."
  end

  def public_action?
    %w[sessions registrations status_page marketing sitemaps].include?(controller_name)
  end

  def current_organization
    Current.organization
  end
  helper_method :current_organization
end

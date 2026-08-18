class ApplicationController < ActionController::Base
  include Authentication

  before_action :redirect_trailing_slash
  before_action :discard_conflicting_pending_session
  before_action :set_current_context
  before_action :require_login

  private

  # Rails recognizes most collection routes with or without a final slash. Keep
  # one public URL for crawlers and links rather than serving two 200 responses
  # with competing self-canonicals. Only redirect safe methods; mutating requests
  # must never be replayed as GET because their path happened to end in a slash.
  def redirect_trailing_slash
    return unless request.get? || request.head?
    raw_path = request.original_fullpath.split("?", 2).first
    return if raw_path == "/" || !raw_path.end_with?("/")

    # Collapse multiple leading slashes so a hostile path can never turn the
    # relative Location into a protocol-relative redirect to another host.
    location = "/#{raw_path.sub(/\A\/+/, "").delete_suffix("/")}"
    location = "#{location}?#{request.query_string}" if request.query_string.present?
    redirect_to location, status: :moved_permanently
  end

  # A session cannot simultaneously be signed in and mid-sign-in as somebody
  # else. Holding both is the precondition for grafting one identity's proof
  # onto another's authentication, so the half-finished one is discarded.
  def discard_conflicting_pending_session
    return if session[:user_id].blank? || session[:pending_user_id].blank?

    abandon_pending_authentication
  end

  def set_current_context
    if session[:user_id]
      user = User.find_by(id: session[:user_id])
      if user
        Current.user = user
        Current.organization = user.organization
      end
    end

    # Deliberately no fallback. Assigning Organization.first to anonymous
    # requests hands every unauthenticated visitor whichever tenant happens to
    # be row #1, and any future public controller inherits it silently.
    # Controllers that serve a specific tenant must resolve it explicitly.
  end

  def require_login
    return if Current.user.present? || public_action?

    # A visitor mid-sign-in is sent back to the step they were on rather than
    # to the password form, which would discard a password they already proved.
    return redirect_to two_factor_path if pending_user&.totp_enabled?
    return redirect_to two_factor_setup_path if pending_user

    redirect_to login_path, alert: "Please sign in to access StatusPulse dashboard."
  end

  def public_action?
    %w[
      sessions registrations status_page marketing sitemaps pwa
      two_factor two_factor_enrolments
    ].include?(controller_name)
  end

  def current_organization
    Current.organization
  end
  helper_method :current_organization

  def require_admin
    return if Current.user&.admin?

    redirect_to dashboard_path, alert: "Only workspace administrators can perform that action."
  end
end

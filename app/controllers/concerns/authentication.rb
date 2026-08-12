# Session handling for a two-step sign-in.
#
# The invariant: session[:user_id] means *fully* authenticated. A password that
# has been accepted but not yet seconded by a code lives in
# session[:pending_user_id] instead. Every existing require_login check
# therefore stays correct with no changes — a half-authenticated visitor simply
# has no user.
module Authentication
  extend ActiveSupport::Concern

  # Sessions are short-lived by design. If the pending step is abandoned, the
  # password proof expires rather than waiting indefinitely for a second factor.
  PENDING_WINDOW = 10.minutes

  included do
    helper_method :pending_user
  end

  def pending_user
    return @pending_user if defined?(@pending_user)

    @pending_user =
      if session[:pending_user_id].present? && pending_within_window?
        User.find_by(id: session[:pending_user_id])
      end
  end

  def begin_pending_authentication(user)
    reset_session
    session[:pending_user_id] = user.id
    session[:pending_started_at] = Time.current.to_i
  end

  # Promotes a pending sign-in to a real one. The session id is rotated so a
  # token captured before the second factor cannot be replayed after it.
  def complete_authentication(user)
    pending_started = session[:pending_started_at]
    reset_session
    session[:user_id] = user.id
    @pending_user = nil
    pending_started
  end

  def abandon_pending_authentication
    session.delete(:pending_user_id)
    session.delete(:pending_started_at)
    @pending_user = nil
  end

  # The freshly-generated recovery codes are held in the session between
  # enrolment and acknowledgement, and their presence is what proves the session
  # completed enrolment.
  #
  # They are stored WITH the id of the account they belong to. A bare array is
  # an identity-less capability: codes minted while acting as one account were
  # accepted as proof for another, which was a full authentication bypass.
  def store_fresh_recovery_codes(user, codes)
    session[:fresh_recovery_codes] = { "user_id" => user.id, "codes" => codes }
  end

  def fresh_recovery_codes_for(user)
    stored = session[:fresh_recovery_codes]
    return nil if stored.blank? || user.nil?
    return nil unless stored["user_id"] == user.id

    stored["codes"].presence
  end

  def discard_fresh_recovery_codes
    session.delete(:fresh_recovery_codes)
  end

  def two_factor_required?
    Rails.configuration.x.require_two_factor
  end

  private

  def pending_within_window?
    started = session[:pending_started_at]
    started.present? && Time.at(started.to_i) > PENDING_WINDOW.ago
  end
end

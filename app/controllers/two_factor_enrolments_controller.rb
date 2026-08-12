# Enrolment: issue a secret, prove the user can generate codes from it, then
# hand over the recovery codes.
#
# The secret is only marked enabled once a code has been verified, so an
# abandoned setup never leaves an account holding a secret nobody has.
#
# Every action here is reachable while only half-authenticated — a password has
# been proved, a second factor has not — which makes each one a candidate
# bypass. The guards below exist to close two that were real:
#
#   * rendering the enrolment page for an already-enrolled account showed its
#     existing secret to anyone holding the password, who could then scan it and
#     answer the challenge themselves;
#   * acknowledging recovery codes completed authentication unconditionally,
#     which turned a single POST into a full sign-in with no second factor at
#     all.
class TwoFactorEnrolmentsController < ApplicationController
  layout "auth"

  rate_limit to: 10, within: 1.minute,
             by: -> { "2fa-setup:#{session[:pending_user_id] || session[:user_id]}" },
             with: -> { redirect_to login_path, alert: "Too many attempts. Please sign in again." },
             only: :create

  before_action :require_enrollable_user, only: [ :new, :create ]
  before_action :require_fresh_enrolment, only: [ :recovery_codes, :confirm_recovery_codes ]

  def new
    # Issue a secret on first arrival, and keep it across a failed attempt so
    # the QR code does not change under someone mid-scan.
    @user.begin_totp_enrolment! if @user.totp_secret.blank?

    @provisioning_uri = @user.totp_provisioning_uri
    @qr_svg = qr_svg(@provisioning_uri)
  end

  def create
    if @user.confirm_totp!(params[:code])
      # Shown exactly once, on the next screen. Held in the session rather than
      # the database because only digests are ever persisted. Its presence is
      # also the proof that this session completed enrolment — see
      # require_fresh_enrolment.
      store_fresh_recovery_codes(@user, RecoveryCode.regenerate_for!(@user))
      return redirect_to two_factor_recovery_codes_path
    end

    @provisioning_uri = @user.totp_provisioning_uri
    @qr_svg = qr_svg(@provisioning_uri)
    flash.now[:alert] = "That code was not valid. Make sure you scanned the code above, then enter the current six digits."
    render :new, status: :unprocessable_entity
  end

  def recovery_codes
  end

  # Acknowledging the codes completes sign-in — but only for a session that
  # actually just enrolled, which require_fresh_enrolment has established.
  def confirm_recovery_codes
    discard_fresh_recovery_codes

    if pending_user
      complete_authentication(@user)
      redirect_to dashboard_path, notice: "Two-factor authentication is on. You're all set."
    else
      redirect_to dashboard_path, notice: "Two-factor authentication is on."
    end
  end

  private

  # Dark modules on white, even though the surrounding interface is dark.
  # Inverted QR codes fail to scan on many phone cameras, and this is the one
  # screen where that failure is silent and maddening. The white quiet zone
  # around it is part of the spec, not decoration.
  def qr_svg(uri)
    RQRCode::QRCode.new(uri).as_svg(
      module_size: 5,
      standalone: true,
      use_path: true,
      color: "000000",
      fill: "ffffff",
      viewbox: true
    ).html_safe
  end

  # Reachable either mid-sign-in (pending) or already signed in (enrolling
  # voluntarily). An account that already holds a second factor is never shown
  # enrolment again: doing so would disclose its secret on the strength of a
  # password alone.
  def require_enrollable_user
    @user = pending_user || Current.user
    return redirect_to login_path, alert: "Your sign-in timed out. Please start again." if @user.nil?
    return unless @user.totp_enabled?

    if pending_user
      redirect_to two_factor_path
    else
      redirect_to dashboard_path, alert: "Two-factor authentication is already on for your account."
    end
  end

  # The codes live in the session only between a successful enrolment and its
  # acknowledgement. Without them there is nothing to display and nothing to
  # acknowledge — and acknowledgement must never itself be a way to sign in.
  def require_fresh_enrolment
    @user = pending_user || Current.user
    return redirect_to login_path, alert: "Your sign-in timed out. Please start again." if @user.nil?

    # Bound to this user, so codes minted while acting as another account are
    # not accepted as proof that *this* one enrolled.
    @codes = fresh_recovery_codes_for(@user)
    return if @codes.present?

    if pending_user
      redirect_to(@user.totp_enabled? ? two_factor_path : two_factor_setup_path)
    else
      redirect_to dashboard_path
    end
  end
end

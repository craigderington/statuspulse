# Enrolment: issue a secret, prove the user can generate codes from it, then
# hand over the recovery codes.
#
# The secret is only marked enabled once a code has been verified, so an
# abandoned setup never leaves an account holding a secret nobody has.
class TwoFactorEnrolmentsController < ApplicationController
  layout "auth"

  rate_limit to: 10, within: 1.minute,
             by: -> { "2fa-setup:#{session[:pending_user_id] || session[:user_id]}" },
             with: -> { redirect_to login_path, alert: "Too many attempts. Please sign in again." },
             only: :create

  before_action :require_enrollable_user

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
      # the database because only digests are ever persisted.
      session[:fresh_recovery_codes] = RecoveryCode.regenerate_for!(@user)
      return redirect_to two_factor_recovery_codes_path
    end

    @provisioning_uri = @user.totp_provisioning_uri
    @qr_svg = qr_svg(@provisioning_uri)
    flash.now[:alert] = "That code was not valid. Make sure you scanned the code above, then enter the current six digits."
    render :new, status: :unprocessable_entity
  end

  def recovery_codes
    @codes = session[:fresh_recovery_codes]

    return redirect_to dashboard_path if @codes.blank?
  end

  # Acknowledging the codes is what completes sign-in — it guarantees the screen
  # was at least dismissed deliberately rather than closed by a redirect.
  def confirm_recovery_codes
    session.delete(:fresh_recovery_codes)

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
  # voluntarily from settings).
  def require_enrollable_user
    @user = pending_user || Current.user

    redirect_to login_path, alert: "Your sign-in timed out. Please start again." if @user.nil?
  end
end

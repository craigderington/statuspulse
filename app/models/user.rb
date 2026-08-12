class User < ApplicationRecord
  ROLES = %w[admin member].freeze

  # A code is accepted one step either side of now, so a user whose clock is a
  # little out still gets in. That widens the window a stolen code stays usable,
  # which is why the consumed timestep is recorded — see #verify_totp.
  TOTP_DRIFT_SECONDS = 30

  has_secure_password

  # Encrypted at rest: a TOTP secret is a second password, and this database is
  # dumped nightly to S3.
  encrypts :totp_secret

  belongs_to :organization
  has_many :recovery_codes, dependent: :destroy

  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :role, inclusion: { in: ROLES }

  def admin?
    role == "admin"
  end

  # ---- two-factor authentication ----

  def totp_enabled?
    totp_enabled_at.present? && totp_secret.present?
  end

  # Issues a fresh secret without enabling anything. Enrolment is only completed
  # once the user proves they can generate a code from it, so an abandoned
  # setup never leaves an account half-protected.
  def begin_totp_enrolment!
    update!(totp_secret: ROTP::Base32.random, totp_enabled_at: nil, totp_last_timestep: nil)
  end

  def totp
    return nil if totp_secret.blank?

    ROTP::TOTP.new(totp_secret, issuer: "StatusPulse")
  end

  def totp_provisioning_uri
    totp&.provisioning_uri(email)
  end

  # Verifies a code and burns the timestep it belongs to.
  #
  # rotp returns the timestamp the code was valid for, which is what makes
  # replay protection possible: a code observed over someone's shoulder is
  # otherwise reusable for the rest of its window.
  def verify_totp(submitted)
    return false if totp.nil?

    code = submitted.to_s.strip.delete("^0-9")
    return false if code.length != 6

    at = totp.verify(code, drift_behind: TOTP_DRIFT_SECONDS, drift_ahead: TOTP_DRIFT_SECONDS)
    return false if at.nil?

    timestep = at.to_i / 30
    return false if totp_last_timestep.present? && timestep <= totp_last_timestep

    update!(totp_last_timestep: timestep)
    true
  end

  # Completes enrolment: the user has proved they hold the secret.
  def confirm_totp!(submitted)
    return false unless verify_totp(submitted)

    update!(totp_enabled_at: Time.current)
    true
  end

  def disable_totp!
    transaction do
      recovery_codes.delete_all
      update!(totp_secret: nil, totp_enabled_at: nil, totp_last_timestep: nil)
    end
  end
end

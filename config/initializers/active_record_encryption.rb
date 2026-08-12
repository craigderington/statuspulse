# Keys for ActiveRecord::Encryption, which protects users.totp_secret.
#
# Kept separate from SECRET_KEY_BASE deliberately. Deriving them from it would
# mean that rotating SECRET_KEY_BASE — something we did once already today —
# silently makes every stored TOTP secret undecryptable, locking every user out
# of their own account with no obvious cause.
#
# In production the keys must be supplied explicitly; a missing key fails at
# boot rather than at the first enrolment. Development and test derive from
# secret_key_base so there is nothing to configure locally.
Rails.application.configure do
  if Rails.env.production?
    missing = %w[
      AR_ENCRYPTION_PRIMARY_KEY
      AR_ENCRYPTION_DETERMINISTIC_KEY
      AR_ENCRYPTION_KEY_DERIVATION_SALT
    ].reject { |name| ENV[name].present? }

    if missing.any?
      raise "Missing ActiveRecord encryption keys: #{missing.join(', ')}. " \
            "Generate with `bin/rails db:encryption:init` and set them in .env."
    end

    config.active_record.encryption.primary_key = ENV["AR_ENCRYPTION_PRIMARY_KEY"]
    config.active_record.encryption.deterministic_key = ENV["AR_ENCRYPTION_DETERMINISTIC_KEY"]
    config.active_record.encryption.key_derivation_salt = ENV["AR_ENCRYPTION_KEY_DERIVATION_SALT"]
  else
    base = Rails.application.secret_key_base
    config.active_record.encryption.primary_key = base[0, 32]
    config.active_record.encryption.deterministic_key = base[32, 32]
    config.active_record.encryption.key_derivation_salt = base[64, 32]
  end
end

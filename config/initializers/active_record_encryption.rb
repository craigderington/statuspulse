# Keys for ActiveRecord::Encryption, which protects users.totp_secret.
#
# Kept separate from SECRET_KEY_BASE deliberately. Deriving them from it would
# mean that rotating SECRET_KEY_BASE — something we did once already today —
# silently makes every stored TOTP secret undecryptable, locking every user out
# of their own account with no obvious cause.
#
# At runtime in production the keys must be supplied explicitly, and a missing
# key fails at boot rather than at the first enrolment.
Rails.application.configure do
  # `assets:precompile` runs during the image build: production environment, no
  # .env, and deliberately no secrets — which is exactly what SECRET_KEY_BASE_DUMMY
  # signals. Demanding real keys there breaks the build for a step that never
  # encrypts anything.
  building_assets = ENV["SECRET_KEY_BASE_DUMMY"].present?

  if Rails.env.production? && !building_assets
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
    # Development, test, and the asset build. Derived so there is nothing to
    # configure locally; nothing encrypted here is ever expected to be readable
    # in production.
    base = Rails.application.secret_key_base
    config.active_record.encryption.primary_key = base[0, 32]
    config.active_record.encryption.deterministic_key = base[32, 32]
    config.active_record.encryption.key_derivation_salt = base[64, 32]
  end
end

require "securerandom"

# A single-use escape hatch for someone who has lost their authenticator.
#
# Stored as a digest only: a recovery code bypasses the second factor entirely,
# so it is password-equivalent and is never recoverable from the database.
class RecoveryCode < ApplicationRecord
  # Ten codes is the industry norm — enough to print or store in a password
  # manager without becoming a list nobody looks after.
  BATCH_SIZE = 10

  # Crockford-ish: no I, L, O, U, so a code read off a screen and typed by hand
  # cannot be transcribed wrongly in the usual ways.
  ALPHABET = "ABCDEFGHJKMNPQRSTVWXYZ23456789".chars.freeze
  GROUP = 5
  GROUPS = 2

  belongs_to :user

  scope :unused, -> { where(used_at: nil) }

  # Returns the plaintext codes. They are shown to the user exactly once; only
  # digests are persisted.
  def self.regenerate_for!(user)
    transaction do
      where(user: user).delete_all

      Array.new(BATCH_SIZE) do
        plaintext = generate
        create!(user: user, code_digest: digest(plaintext))
        plaintext
      end
    end
  end

  # Consumes a code if it matches an unused one. Comparison is over digests, and
  # every candidate is checked so that a match late in the list does not take
  # measurably longer than one at the start.
  def self.consume!(user, submitted)
    normalized = normalize(submitted)
    return false if normalized.blank?

    target = digest(normalized)
    match = nil

    unused.where(user: user).find_each do |code|
      match = code if ActiveSupport::SecurityUtils.secure_compare(code.code_digest, target)
    end

    return false if match.nil?

    match.update!(used_at: Time.current)
    true
  end

  def self.generate
    Array.new(GROUPS) { Array.new(GROUP) { ALPHABET.sample(random: SecureRandom) }.join }.join("-")
  end

  # Accepts what a person actually types: lowercase, missing hyphen, stray
  # spaces. The alphabet excludes the ambiguous letters, so this cannot collapse
  # two distinct codes into one.
  def self.normalize(value)
    value.to_s.strip.upcase.delete("^A-Z0-9")
  end

  # Normalizes before hashing so that the digest written at generation (from a
  # hyphenated code) and the digest computed at redemption (from whatever the
  # user typed) are the same value.
  def self.digest(plaintext)
    OpenSSL::Digest::SHA256.hexdigest("#{normalize(plaintext)}#{Rails.application.secret_key_base}")
  end

  def used?
    used_at.present?
  end
end

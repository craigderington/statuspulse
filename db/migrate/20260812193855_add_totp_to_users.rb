class AddTotpToUsers < ActiveRecord::Migration[8.1]
  def change
    # Encrypted at rest via ActiveRecord::Encryption — a TOTP secret in a
    # plaintext column is a second password sitting in the database and in every
    # offsite backup. Sized generously because ciphertext is much larger than
    # the 32-character base32 secret it wraps.
    add_column :users, :totp_secret, :text

    add_column :users, :totp_enabled_at, :datetime

    # Replay protection. A code is accepted across a small drift window, so
    # without recording the timestep it was issued for, an observed code works
    # again until it expires.
    add_column :users, :totp_last_timestep, :bigint

    create_table :recovery_codes do |t|
      t.references :user, null: false, foreign_key: true
      # Digest only. Recovery codes are password-equivalent: they bypass the
      # second factor entirely, so they are never stored recoverably.
      t.string :code_digest, null: false
      t.datetime :used_at
      t.timestamps
    end

    add_index :recovery_codes, [ :user_id, :used_at ]
  end
end

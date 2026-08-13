class AddTlsMonitoringToServices < ActiveRecord::Migration[8.1]
  def change
    # Certificates were previously not validated at all (VERIFY_NONE), so an
    # expired or mismatched cert passed silently while a real browser refused
    # to connect. Verification is now the default; the opt-out exists for
    # internal endpoints and self-signed certificates.
    add_column :services, :verify_tls, :boolean, default: true, null: false

    # Observed during the check that already happens rather than fetched
    # separately — every HTTPS request establishes a TLS session, so the
    # certificate is already in hand.
    add_column :services, :tls_expires_at, :datetime
    add_column :services, :tls_issuer, :string

    # One warning per certificate, not one per check. Cleared when the
    # certificate changes, so a renewal re-arms it.
    add_column :services, :tls_alerted_at, :datetime
  end
end

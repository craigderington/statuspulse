class AddAlertingToServicesAndOrganizations < ActiveRecord::Migration[8.1]
  def change
    # Consecutive failures, not a total: one failed check is usually a blip —
    # a dropped packet, a slow DNS lookup, a container restarting mid-deploy.
    # Alerting on every one is how alerting gets muted.
    add_column :services, :consecutive_failures, :integer, default: 0, null: false

    # When we last told anyone this service was down. Its presence is what stops
    # an alert repeating every minute for the duration of an outage, and its
    # absence is what makes a recovery notice meaningful.
    add_column :services, :alerted_at, :datetime

    # Alerts go to everyone in the workspace, so the webhook belongs to the
    # organization rather than the service.
    add_column :organizations, :alert_webhook_url, :string
    add_column :organizations, :alert_webhook_secret, :string
    add_column :organizations, :alerts_enabled, :boolean, default: true, null: false
  end
end

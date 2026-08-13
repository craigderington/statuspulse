# Alert and email settings for the workspace.
#
# Admin-only, like workspace settings: turning alerts off, or repointing the
# webhook, changes what everyone in the workspace is told when a client goes
# down.
class AlertSettingsController < ApplicationController
  before_action :require_admin
  before_action :set_organization

  # A test posts to a customer-supplied URL on demand, so it is throttled to
  # stop the endpoint being used to make the server issue arbitrary requests.
  rate_limit to: 5, within: 1.minute,
             by: -> { "webhook-test:#{session[:user_id]}" },
             with: -> { redirect_to alert_settings_path, alert: "Too many tests. Please wait a minute." },
             only: :test_webhook

  def edit
  end

  def update
    if @organization.update(alert_settings_params)
      redirect_to alert_settings_path, notice: "Alert settings saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Sends a real payload, signed exactly like a real alert, so the receiving end
  # can be verified before an outage rather than during one.
  def test_webhook
    if @organization.alert_webhook_url.blank?
      return redirect_to alert_settings_path, alert: "Add a webhook URL first."
    end

    sample = @organization.services.ordered.first
    if sample.nil?
      return redirect_to alert_settings_path,
        alert: "Add a service first — the test payload describes a real one."
    end

    require Rails.root.join("lib/alert_webhook_delivery")
    AlertWebhookDelivery.new(@organization).deliver!(
      kind: "down", service: sample, error_message: "Test alert from StatusPulse"
    )

    redirect_to alert_settings_path, notice: "Test delivered — your endpoint returned a success response."
  rescue StandardError => e
    Rails.logger.warn("Webhook test failed for organization #{@organization.id}: #{e.class}: #{e.message}")
    redirect_to alert_settings_path, alert: "Test failed: #{e.message}"
  end

  private

  def set_organization
    @organization = current_organization
  end

  def require_admin
    return if Current.user&.admin?

    redirect_to dashboard_path, alert: "Only workspace admins can change these settings."
  end

  def alert_settings_params
    params.require(:organization).permit(:alerts_enabled, :alert_webhook_url, :weekly_digest_enabled)
  end
end

# Delivers a down or recovery alert for a service.
#
# Runs async so that a slow mail API or an unresponsive customer webhook cannot
# stall the check sweep — one workspace's misconfigured endpoint must not delay
# everybody else's monitoring.
class ServiceAlertJob < ApplicationJob
  queue_as :default

  def perform(service_id, kind, error_message = nil, downtime_started_at = nil)
    service = Service.find_by(id: service_id)
    return if service.nil?

    organization = service.organization
    return if organization.nil? || !organization.alerts_enabled?

    started_at = downtime_started_at.present? ? Time.zone.parse(downtime_started_at) : nil

    deliver_email(service, organization, kind, error_message, started_at)
    deliver_webhook(service, organization, kind, error_message, started_at)
  end

  private

  # Email and webhook are delivered independently: a rejected email must not
  # stop the webhook that an on-call rotation depends on, and vice versa.
  def deliver_email(service, organization, kind, error_message, started_at)
    recipients = organization.users.pluck(:email)
    return if recipients.empty?

    mail = if kind == "down"
      ServiceAlertMailer.service_down(service, recipients, error_message)
    else
      ServiceAlertMailer.service_recovered(service, recipients, started_at)
    end

    mail.deliver_now
  rescue StandardError => e
    Rails.logger.error("ServiceAlertJob email failed for service #{service.id}: #{e.class}: #{e.message}")
  end

  def deliver_webhook(service, organization, kind, error_message, started_at)
    return if organization.alert_webhook_url.blank?

    AlertWebhookDelivery.new(organization).deliver!(
      kind: kind,
      service: service,
      error_message: error_message,
      downtime_started_at: started_at
    )
  rescue StandardError => e
    Rails.logger.error("ServiceAlertJob webhook failed for service #{service.id}: #{e.class}: #{e.message}")
  end
end

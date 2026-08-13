class ServiceAlertMailer < ApplicationMailer
  # Alerts are read on a phone, at night, by someone deciding whether to get up.
  # The subject line carries the whole message: what broke, and which client.
  def service_down(service, recipients, error_message = nil)
    @service = service
    @organization = service.organization
    @error_message = error_message
    @status_url = status_url_for(@organization)

    mail(
      to: recipients,
      subject: "[#{@organization.name}] #{@service.name} is down"
    )
  end

  def service_recovered(service, recipients, downtime_started_at = nil)
    @service = service
    @organization = service.organization
    @downtime_started_at = downtime_started_at
    @downtime = downtime_started_at ? distance_of_time_in_words(downtime_started_at, Time.current) : nil
    @status_url = status_url_for(@organization)

    mail(
      to: recipients,
      subject: "[#{@organization.name}] #{@service.name} is back up"
    )
  end

  private

  include ActionView::Helpers::DateHelper

  def status_url_for(organization)
    return nil if organization&.slug.blank?

    org_public_status_url(org_slug: organization.slug)
  end
end

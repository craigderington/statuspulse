class WeeklyDigestMailer < ApplicationMailer
  default from: "reports@statuspulse.org"

  def digest_email(organization)
    @organization = organization
    @services = organization.services.ordered
    @recipients = organization.users.pluck(:email)

    return if @recipients.empty?

    @avg_uptime = organization.average_uptime_percentage(7.days)
    @avg_latency = organization.average_response_latency(7.days)
    @incidents_count = organization.incidents.where("created_at >= ?", 7.days.ago).count

    mail(
      to: @recipients,
      subject: "📊 StatusPulse Weekly Uptime Digest — #{organization.name} (#{@avg_uptime}% Uptime)"
    )
  end
end

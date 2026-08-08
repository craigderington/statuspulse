class StatusPageController < ApplicationController
  layout "status_page"

  def show
    if params[:org_slug].present?
      @organization = Organization.find_by!(slug: params[:org_slug])
    else
      @organization = current_organization || Organization.first
    end

    @services = @organization ? @organization.services.ordered : Service.ordered
    @active_incidents = @organization ? @organization.incidents.active : Incident.active
    @recent_incidents = @organization ? @organization.incidents.recent.limit(10) : Incident.recent.limit(10)

    @overall_status = calculate_overall_status
    @overall_uptime = calculate_avg_uptime
  end

  private

  def calculate_overall_status
    statuses = @services.map(&:status)
    return "outage" if statuses.include?("outage")
    return "degraded" if statuses.include?("degraded")
    "operational"
  end

  def calculate_avg_uptime
    return 100.0 if @services.empty?
    (@services.sum(&:uptime_percentage) / @services.size).round(2)
  end
end

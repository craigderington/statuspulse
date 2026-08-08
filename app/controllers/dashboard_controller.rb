class DashboardController < ApplicationController
  def index
    @services = current_organization ? current_organization.services.ordered : Service.ordered
    @active_incidents = current_organization ? current_organization.incidents.active : Incident.active
    @recent_incidents = current_organization ? current_organization.incidents.recent.limit(5) : Incident.recent.limit(5)

    @overall_status = calculate_overall_status
    @avg_uptime = calculate_avg_uptime
    @avg_response_time = calculate_avg_response_time
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

  def calculate_avg_response_time
    return 0 if @services.empty?
    (@services.sum(&:average_response_time_ms) / @services.size).round
  end
end

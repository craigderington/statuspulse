class StatusPageController < ApplicationController
  layout "status_page"

  def show
    if params[:org_slug].blank?
      organization = resolve_platform_organization
      raise ActiveRecord::RecordNotFound if organization.nil?

      return redirect_to org_public_status_path(org_slug: organization.slug), status: :moved_permanently
    end

    @organization = Organization.find_by!(slug: params[:org_slug])

    @services = @organization.services.ordered
    @active_incidents = @organization.incidents.active
    @recent_incidents = @organization.incidents.recent.limit(10)

    @overall_status = calculate_overall_status
    @overall_uptime = calculate_avg_uptime
  end

  private

  def resolve_platform_organization
    platform_slug = ENV["PLATFORM_STATUS_SLUG"].presence
    platform_slug && Organization.find_by(slug: platform_slug)
  end

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

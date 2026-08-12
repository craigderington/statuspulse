class StatusPageController < ApplicationController
  layout "status_page"

  def show
    @organization = resolve_organization

    # No degrading to "every service on the platform". A status page without a
    # tenant is not a status page; rendering one unscoped would publish every
    # tenant's services, incidents and URLs on a public page.
    raise ActiveRecord::RecordNotFound if @organization.nil?

    @services = @organization.services.ordered
    @active_incidents = @organization.incidents.active
    @recent_incidents = @organization.incidents.recent.limit(10)

    @overall_status = calculate_overall_status
    @overall_uptime = calculate_avg_uptime
  end

  private

  # /status/<slug> names its tenant. Bare /status resolves to the platform's own
  # status page, named explicitly by PLATFORM_STATUS_SLUG rather than inferred
  # from row order.
  def resolve_organization
    return Organization.find_by!(slug: params[:org_slug]) if params[:org_slug].present?

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

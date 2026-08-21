class MarketingController < ApplicationController
  layout "marketing"

  # The public landing page. Signed-in operators never see it — they came here
  # for the dashboard, not the sales pitch.
  def index
    return redirect_to dashboard_path if Current.user.present?

    @sample_workspaces = SAMPLE_WORKSPACES
  end

  def agencies
  end

  def multi_tenant
  end

  def reports
  end

  def compare
  end

  def pricing
  end

  def about
  end

  def contact
  end

  def privacy
  end

  def terms
  end

  # Illustrative content for the hero wall. Fictional client names, clearly a
  # product mock: nothing here is presented as a real customer or a real metric.
  SAMPLE_WORKSPACES = [
    { name: "Northwind Logistics", slug: "northwind", latency: 128, status: "operational" },
    { name: "Meridian Health",     slug: "meridian",  latency: 214, status: "operational" },
    { name: "Kestrel Payments",    slug: "kestrel",   latency: 96,  status: "operational" },
    { name: "Alder & Vane",        slug: "alder",     latency: 342, status: "operational" }
  ].freeze
end

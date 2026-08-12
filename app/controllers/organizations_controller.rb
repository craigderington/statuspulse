class OrganizationsController < ApplicationController
  before_action :require_admin
  before_action :set_organization

  def edit
  end

  def update
    previous_slug = @organization.slug

    if @organization.update(organization_params)
      redirect_to edit_organization_path, notice: notice_for(previous_slug)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  # You always edit your own workspace; there is no organization id in the URL
  # to tamper with.
  def set_organization
    @organization = current_organization
  end

  def require_admin
    return if Current.user&.admin?

    redirect_to dashboard_path, alert: "Only workspace admins can change these settings."
  end

  def organization_params
    params.require(:organization).permit(:name, :slug, :weekly_digest_enabled, :status_page_indexable)
  end

  # Changing the slug changes a public URL that clients may have bookmarked, so
  # say so plainly rather than reporting a generic success.
  def notice_for(previous_slug)
    if @organization.slug == previous_slug
      "Workspace settings saved."
    else
      "Settings saved. Your status page has moved to /status/#{@organization.slug} — /status/#{previous_slug} no longer resolves."
    end
  end
end

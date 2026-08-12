class SitemapsController < ApplicationController
  layout false

  # Rendered rather than a static file so opted-in client status pages appear as
  # soon as they exist, without anyone remembering to regenerate anything.
  def show
    @organizations = Organization.where(status_page_indexable: true).order(:slug)

    respond_to do |format|
      format.xml
    end
  end
end

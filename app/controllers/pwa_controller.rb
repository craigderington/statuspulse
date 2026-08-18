class PwaController < ApplicationController
  layout false
  skip_forgery_protection only: :service_worker

  def manifest
    render formats: :json, content_type: "application/manifest+json"
  end

  def service_worker
    render template: "pwa/service-worker", formats: :js, content_type: "text/javascript"
  end
end

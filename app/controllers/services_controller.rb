class ServicesController < ApplicationController
  before_action :set_service, only: [ :show, :edit, :update, :destroy, :check_now, :pause, :resume ]
  before_action :require_admin, except: [ :index, :show ]

  def index
    @services = scope_services.ordered
  end

  CHECKS_PER_PAGE = 50

  def show
    scope = @service.check_logs.recent

    @checks_total = scope.count
    @checks_pages = [ (@checks_total / CHECKS_PER_PAGE.to_f).ceil, 1 ].max
    # Clamp rather than 404: a stale link to page 90 after a purge should land
    # on the last page, not an error.
    @checks_page = params[:page].to_i.clamp(1, @checks_pages)

    @checks_offset = (@checks_page - 1) * CHECKS_PER_PAGE
    @check_logs = scope.offset(@checks_offset).limit(CHECKS_PER_PAGE)
  end

  def new
    @service = scope_services.new(
      http_method: "GET",
      expected_status_code: 200,
      check_interval_seconds: 60,
      timeout_seconds: 10
    )
  end

  def create
    @service = scope_services.new(service_params)
    @service.organization = current_organization

    if @service.save
      redirect_to @service, notice: "Service '#{@service.name}' was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @service.update(service_params)
      redirect_to @service, notice: "Service '#{@service.name}' was updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @service.destroy
    redirect_to services_url, notice: "Service was removed."
  end

  def check_now
    @service.perform_check!
    respond_to do |format|
      format.html { redirect_to @service, notice: "Manual check triggered for #{@service.name}." }
      format.turbo_stream
    end
  end

  def pause
    @service.pause!
    redirect_to @service, notice: "Monitoring suspended for #{@service.name}. Paused time is excluded from SLA."
  end

  def resume
    @service.resume!
    redirect_to @service, notice: "Monitoring resumed for #{@service.name}."
  end

  private

  def scope_services
    current_organization.services
  end

  def set_service
    @service = scope_services.find(params[:id])
  end

  def service_params
    params.require(:service).permit(
      :name, :description, :url, :http_method, :headers, :request_body,
      :expected_body_match, :expected_status_code, :timeout_seconds,
      :check_interval_seconds, :position, :status, :verify_tls
    )
  end
end

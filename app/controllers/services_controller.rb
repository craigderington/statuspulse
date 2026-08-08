class ServicesController < ApplicationController
  before_action :set_service, only: [:show, :edit, :update, :destroy, :check_now]

  def index
    @services = scope_services.ordered
  end

  def show
    @check_logs = @service.check_logs.recent.limit(50)
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

  private

  def scope_services
    current_organization ? current_organization.services : Service.all
  end

  def set_service
    @service = scope_services.find(params[:id])
  end

  def service_params
    params.require(:service).permit(
      :name, :description, :url, :http_method, :headers, :request_body,
      :expected_body_match, :expected_status_code, :timeout_seconds,
      :check_interval_seconds, :position, :status
    )
  end
end

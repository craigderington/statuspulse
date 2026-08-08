class IncidentsController < ApplicationController
  before_action :set_incident, only: [:show, :edit, :update, :destroy]

  def index
    @active_incidents = Incident.active
    @resolved_incidents = Incident.resolved
  end

  def show
    @incident_updates = @incident.incident_updates.order(created_at: :desc)
    @new_update = @incident.incident_updates.new(status: @incident.status)
  end

  def new
    @incident = Incident.new(severity: "degraded", status: "investigating")
  end

  def create
    @incident = Incident.new(incident_params)

    if @incident.save
      if params[:service_ids].present?
        @incident.service_ids = params[:service_ids]
      end
      redirect_to @incident, notice: "Incident logged successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @incident.update(incident_params)
      if params[:service_ids].present?
        @incident.service_ids = params[:service_ids]
      end
      redirect_to @incident, notice: "Incident updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @incident.destroy
    redirect_to incidents_url, notice: "Incident removed."
  end

  private

  def set_incident
    @incident = Incident.find(params[:id])
  end

  def incident_params
    params.require(:incident).permit(:title, :description, :status, :severity)
  end
end

class IncidentsController < ApplicationController
  before_action :set_incident, only: [ :show, :edit, :update, :destroy ]
  before_action :require_admin, except: [ :index, :show ]
  before_action :set_available_services, only: [ :new, :create, :edit, :update ]

  def index
    @active_incidents = current_organization.incidents.active
    @resolved_incidents = current_organization.incidents.resolved
  end

  def show
    @incident_updates = @incident.incident_updates.order(created_at: :desc)
    @new_update = @incident.incident_updates.new(status: @incident.status)
  end

  def new
    @incident = current_organization.incidents.new(severity: "degraded", status: "investigating")
  end

  def create
    @incident = current_organization.incidents.new(incident_params)

    if save_with_services(@incident)
      redirect_to @incident, notice: "Incident logged successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @incident.assign_attributes(incident_params)
    if save_with_services(@incident)
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
    @incident = current_organization.incidents.find(params[:id])
  end

  def incident_params
    params.require(:incident).permit(:title, :description, :status, :severity)
  end


  def set_available_services
    @available_services = current_organization.services.ordered
  end

  def save_with_services(incident)
    requested_ids = Array(params[:service_ids]).reject(&:blank?).map(&:to_s).uniq
    services = current_organization.services.where(id: requested_ids).to_a
    raise ActiveRecord::RecordNotFound if services.length != requested_ids.length

    incident.transaction do
      incident.save!
      incident.services = services
    end
    true
  rescue ActiveRecord::RecordInvalid
    false
  end
end

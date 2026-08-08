class IncidentUpdatesController < ApplicationController
  def create
    @incident = Incident.find(params[:incident_id])
    @update = @incident.incident_updates.new(update_params)

    if @update.save
      redirect_to @incident, notice: "Incident update posted."
    else
      redirect_to @incident, alert: "Failed to post update: #{@update.errors.full_messages.join(', ')}"
    end
  end

  private

  def update_params
    params.require(:incident_update).permit(:body, :status)
  end
end

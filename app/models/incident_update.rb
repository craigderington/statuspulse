class IncidentUpdate < ApplicationRecord
  belongs_to :incident

  validates :body, presence: true
  validates :status, inclusion: { in: Incident::STATUSES }

  after_create_commit :update_parent_incident_status

  private

  def update_parent_incident_status
    attrs = { status: status }
    attrs[:resolved_at] = Time.current if status == "resolved"
    incident.update!(attrs)
  end
end

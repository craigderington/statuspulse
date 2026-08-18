class IncidentService < ApplicationRecord
  belongs_to :incident
  belongs_to :service
  belongs_to :organization

  before_validation :copy_organization
  validate :same_organization

  private

  def copy_organization
    self.organization ||= incident&.organization
  end

  def same_organization
    return if incident.nil? || service.nil?
    return if incident.organization_id == service.organization_id &&
              organization_id == incident.organization_id

    errors.add(:service, "must belong to the incident workspace")
  end
end

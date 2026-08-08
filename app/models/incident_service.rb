class IncidentService < ApplicationRecord
  belongs_to :incident
  belongs_to :service
end

class ServiceCheckJob < ApplicationJob
  queue_as :default

  def perform(service_id = nil)
    if service_id.present?
      Service.find_by(id: service_id)&.perform_check!
    else
      Service.find_each(&:perform_check!)
    end
  end
end

class ServiceCheckJob < ApplicationJob
  queue_as :default

  # Runs every minute from config/recurring.yml. Without an id it sweeps every
  # service but only checks the ones whose own check_interval_seconds has
  # elapsed, so a 300s service is not polled every 60s.
  #
  # An explicit service_id forces an immediate check regardless of interval,
  # which is what the manual "ping now" action uses.
  def perform(service_id = nil)
    if service_id.present?
      Service.find_by(id: service_id)&.perform_check!
    else
      Service.find_each do |service|
        next unless service.due_for_check?

        begin
          service.perform_check!
        rescue StandardError => e
          # One unreachable endpoint must not abort the sweep for the rest.
          Rails.logger.error("ServiceCheckJob failed for service #{service.id}: #{e.class}: #{e.message}")
        end
      end
    end
  end
end

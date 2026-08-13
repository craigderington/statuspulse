class CheckLog < ApplicationRecord
  # How long check history is kept. A service checked every 60s writes 1,440
  # rows a day, so this table is the only one in the app that grows without
  # bound — roughly 5M rows a year across ten services, every one of which is
  # scanned by uptime_percentage on each dashboard load.
  #
  # 90 days is the longest window the product actually reports on. Reports are
  # clamped to it (see ReportsController) so a longer request can never be
  # answered from partial data.
  def self.retention_days
    ENV.fetch("CHECK_LOG_RETENTION_DAYS", 90).to_i
  end

  def self.retention_cutoff
    retention_days.days.ago
  end

  belongs_to :service

  scope :recent, -> { order(created_at: :desc) }
  scope :expired, -> { where(created_at: ...retention_cutoff) }
  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }
  scope :for_period, ->(start_time, end_time = Time.current) { where(created_at: start_time..end_time) }
end

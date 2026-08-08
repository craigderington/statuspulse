class MaintenanceWindow < ApplicationRecord
  STATUSES = %w[scheduled in_progress completed cancelled].freeze

  validates :title, presence: true
  validates :starts_at, presence: true
  validates :ends_at, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :upcoming, -> { where("starts_at > ?", Time.current).order(starts_at: :asc) }
  scope :active, -> { where("starts_at <= ? AND ends_at >= ?", Time.current, Time.current) }
  scope :recent, -> { order(starts_at: :desc) }
end

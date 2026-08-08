class CheckLog < ApplicationRecord
  belongs_to :service

  scope :recent, -> { order(created_at: :desc) }
  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }
  scope :for_period, ->(start_time, end_time = Time.current) { where(created_at: start_time..end_time) }
end

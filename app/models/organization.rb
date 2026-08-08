class Organization < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :services, dependent: :destroy
  has_many :incidents, dependent: :destroy
  has_many :maintenance_windows, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9\-]+\z/, message: "only lowercase letters, numbers and hyphens allowed" }

  before_validation :generate_slug, on: :create

  def average_uptime_percentage(period = 30.days)
    return 100.0 if services.empty?
    (services.map { |s| s.uptime_percentage(period) }.sum / services.size).round(2)
  end

  def average_response_latency(period = 24.hours)
    return 0 if services.empty?
    (services.map { |s| s.average_response_time_ms(period) }.sum / services.size).round
  end

  private

  def generate_slug
    self.slug ||= name.to_s.parameterize if name.present?
  end
end

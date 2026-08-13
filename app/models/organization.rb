class Organization < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :services, dependent: :destroy
  has_many :incidents, dependent: :destroy
  has_many :maintenance_windows, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
            format: { with: /\A[a-z0-9\-]+\z/, message: "can use only lowercase letters, numbers and hyphens" }

  before_validation :generate_slug, on: :create
  before_validation :ensure_alert_webhook_secret

  # Validated here as well as at delivery time. The delivery check is the one
  # that counts — DNS can change between the two — but rejecting an obviously
  # unusable URL at the form is far kinder than a silent failure at 3am.
  validate :alert_webhook_url_is_deliverable

  def alert_webhook_configured?
    alert_webhook_url.present?
  end

  def average_uptime_percentage(period = 30.days)
    return 100.0 if services.empty?
    (services.map { |s| s.uptime_percentage(period) }.sum / services.size).round(2)
  end

  def average_response_latency(period = 24.hours)
    return 0 if services.empty?
    (services.map { |s| s.average_response_time_ms(period) }.sum / services.size).round
  end

  private

  def ensure_alert_webhook_secret
    return if alert_webhook_url.blank?
    return if alert_webhook_secret.present?

    self.alert_webhook_secret = SecureRandom.hex(32)
  end

  # Syntax and literal addresses only — no DNS. Resolution happens at delivery,
  # so a host that is momentarily unresolvable never blocks saving settings.
  def alert_webhook_url_is_deliverable
    return if alert_webhook_url.blank?

    require Rails.root.join("lib/alert_webhook_delivery")
    AlertWebhookDelivery.validate_format!(alert_webhook_url)
  rescue AlertWebhookDelivery::UnsafeDestination => e
    errors.add(:alert_webhook_url, e.message)
  end

  def generate_slug
    self.slug ||= name.to_s.parameterize if name.present?
  end
end

class Incident < ApplicationRecord
  STATUSES = %w[investigating identified monitoring resolved].freeze
  SEVERITIES = %w[degraded partial_outage major_outage].freeze

  belongs_to :organization, optional: true
  has_many :incident_services, dependent: :destroy
  has_many :services, through: :incident_services
  has_many :incident_updates, dependent: :destroy

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :severity, inclusion: { in: SEVERITIES }

  scope :active, -> { where.not(status: "resolved").order(created_at: :desc) }
  scope :resolved, -> { where(status: "resolved").order(resolved_at: :desc) }
  scope :recent, -> { order(created_at: :desc) }

  after_create_commit :create_initial_update

  def active?
    status != "resolved"
  end

  private

  def create_initial_update
    incident_updates.create!(
      status: status,
      body: description.presence || "Incident reported. Team is investigating the issue."
    )
  end
end

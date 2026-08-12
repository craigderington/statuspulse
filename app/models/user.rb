class User < ApplicationRecord
  ROLES = %w[admin member].freeze

  has_secure_password

  belongs_to :organization

  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :role, inclusion: { in: ROLES }

  def admin?
    role == "admin"
  end
end

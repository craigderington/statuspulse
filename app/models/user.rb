class User < ApplicationRecord
  has_secure_password

  belongs_to :organization

  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
end

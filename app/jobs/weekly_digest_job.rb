class WeeklyDigestJob < ApplicationJob
  queue_as :default

  def perform
    Organization.where(weekly_digest_enabled: true).find_each do |org|
      WeeklyDigestMailer.digest_email(org).deliver_later
    end
  end
end

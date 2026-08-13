# Preview all emails at http://localhost:3000/rails/mailers/weekly_digest_mailer
class WeeklyDigestMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/weekly_digest_mailer/digest_email
  #
  # digest_email requires an organization, and returns early unless that
  # organization has at least one user to address, so prefer an org that has
  # both services and users — otherwise the preview renders an empty shell.
  def digest_email
    WeeklyDigestMailer.digest_email(preview_organization)
  end

  private

  def preview_organization
    Organization.joins(:users).joins(:services).distinct.first ||
      Organization.joins(:users).distinct.first ||
      Organization.first
  end
end

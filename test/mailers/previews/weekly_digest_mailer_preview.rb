# Preview all emails at http://localhost:3000/rails/mailers/weekly_digest_mailer
class WeeklyDigestMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/weekly_digest_mailer/digest_email
  def digest_email
    WeeklyDigestMailer.digest_email
  end
end

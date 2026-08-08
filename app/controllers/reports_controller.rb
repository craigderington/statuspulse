class ReportsController < ApplicationController
  def index
    @organization = current_organization
    @services = @organization.services.ordered
    @incidents = @organization.incidents.recent.limit(10)

    @period_days = (params[:days].presence || 30).to_i
    @start_date = @period_days.days.ago

    @reports_data = @services.map do |service|
      logs = service.check_logs.for_period(@start_date)
      total = logs.count
      successful = logs.successful.count
      failed = logs.failed.count

      uptime_pct = total.positive? ? ((successful.to_f / total) * 100).round(3) : 100.0

      latencies = logs.successful.pluck(:response_time_ms).sort
      avg_latency = latencies.any? ? (latencies.sum / latencies.size).round : 0
      p90_latency = latencies.any? ? latencies[(latencies.size * 0.90).to_i] : 0

      {
        service: service,
        total_checks: total,
        successful_checks: successful,
        failed_checks: failed,
        uptime_percentage: uptime_pct,
        average_latency_ms: avg_latency,
        p90_latency_ms: p90_latency
      }
    end
  end

  def send_test_email
    WeeklyDigestMailer.digest_email(current_organization).deliver_now rescue nil
    redirect_to reports_path, notice: "Weekly digest report email dispatched to organization team members!"
  end
end

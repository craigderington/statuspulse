require "net/http"
require "uri"
require "json"

class Service < ApplicationRecord
  HTTP_METHODS = %w[GET POST PUT HEAD PATCH DELETE OPTIONS].freeze
  STATUSES = %w[operational degraded outage maintenance].freeze

  belongs_to :organization, optional: true
  has_many :check_logs, dependent: :destroy
  has_many :incident_services, dependent: :destroy
  has_many :incidents, through: :incident_services

  validates :name, presence: true
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a valid HTTP or HTTPS URL" }
  validates :http_method, inclusion: { in: HTTP_METHODS }
  validates :expected_status_code, numericality: { only_integer: true, greater_than_or_equal_to: 100, less_than: 600 }
  validates :timeout_seconds, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 60 }
  validates :status, inclusion: { in: STATUSES }

  after_update_commit -> { broadcast_replace_to "services_status", target: "service_#{id}", partial: "services/service_card", locals: { service: self } }

  scope :ordered, -> { order(position: :asc, name: :asc) }

  # Parses HTTP headers from either JSON or line-by-line format "Header-Name: Value"
  def parsed_headers
    return {} if headers.blank?

    # Try JSON parsing
    JSON.parse(headers)
  rescue JSON::ParserError
    parsed = {}
    headers.to_s.each_line do |line|
      line = line.strip
      next if line.blank? || !line.include?(":")

      key, val = line.split(":", 2)
      parsed[key.strip] = val.strip if key.present?
    end
    parsed
  end

  def perform_check!
    uri = URI.parse(url)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = timeout_seconds
    http.read_timeout = timeout_seconds
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE # Flexible for local dev/self-signed endpoints

    request_class = Net::HTTP.const_get(http_method.capitalize) rescue Net::HTTP::Get
    request = request_class.new(uri.request_uri)

    # Apply default User-Agent if not provided
    request["User-Agent"] = "StatusPulse-Monitor/1.0 (+https://statuspulse.org)"
    parsed_headers.each do |k, v|
      request[k] = v
    end

    if %w[POST PUT PATCH].include?(http_method.upcase) && request_body.present?
      request.body = request_body
    end

    response = http.request(request)
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

    code_match = (response.code.to_i == expected_status_code)
    body_match = expected_body_match.blank? || (response.body && response.body.include?(expected_body_match))

    is_success = code_match && body_match
    error_msg = nil

    unless is_success
      reasons = []
      reasons << "Expected HTTP #{expected_status_code}, got #{response.code}" unless code_match
      reasons << "Response body missing '#{expected_body_match}'" unless body_match
      error_msg = reasons.join("; ")
    end

    new_status = determine_new_status(is_success, duration_ms)

    update!(
      status: new_status,
      last_checked_at: Time.current,
      last_response_time_ms: duration_ms,
      last_status_code: response.code.to_i
    )

    check_logs.create!(
      status_code: response.code.to_i,
      response_time_ms: duration_ms,
      success: is_success,
      error_message: error_msg
    )
  rescue StandardError => e
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round rescue 0

    update!(
      status: "outage",
      last_checked_at: Time.current,
      last_response_time_ms: duration_ms,
      last_status_code: 0
    )

    check_logs.create!(
      status_code: 0,
      response_time_ms: duration_ms,
      success: false,
      error_message: e.message
    )
  end

  def uptime_percentage(period = 30.days)
    logs = check_logs.for_period(period.ago)
    total = logs.count
    return 100.0 if total.zero?

    successes = logs.successful.count
    ((successes.to_f / total) * 100).round(2)
  end

  def average_response_time_ms(period = 24.hours)
    logs = check_logs.successful.for_period(period.ago)
    return 0 if logs.empty?

    logs.average(:response_time_ms).to_f.round
  end

  def history_bars(count = 45)
    # Returns last N days/checks status for timeline visualizer
    recent_logs = check_logs.recent.limit(count).to_a.reverse
    if recent_logs.size < count
      pad_count = count - recent_logs.size
      pad_count.times.map { { success: nil, code: nil, latency: 0 } } + recent_logs.map { |l| { success: l.success, code: l.status_code, latency: l.response_time_ms, date: l.created_at } }
    else
      recent_logs.map { |l| { success: l.success, code: l.status_code, latency: l.response_time_ms, date: l.created_at } }
    end
  end

  private

  def determine_new_status(is_success, duration_ms)
    return "outage" unless is_success
    return "degraded" if duration_ms > 2500 # High latency threshold
    "operational"
  end
end

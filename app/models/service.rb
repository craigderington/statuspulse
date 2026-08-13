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

  # Streams are scoped per organization. A single global stream name would
  # broadcast every tenant's service telemetry — names, URLs, latency, status —
  # to every other tenant's dashboard in real time.
  after_create_commit -> { broadcast_prepend_to organization_stream, target: "services_list", partial: "services/service_card", locals: { service: self } }
  after_update_commit -> { broadcast_replace_to organization_stream, target: "service_#{id}", partial: "services/service_card", locals: { service: self } }
  after_destroy_commit -> { broadcast_remove_to organization_stream, target: "service_#{id}" }

  def organization_stream
    [ organization, "services_status" ]
  end

  # Two consecutive failures, not one. A single failed check is usually a blip —
  # a dropped packet, a slow DNS lookup, a container restarting mid-deploy — and
  # alerting on every one is how alerting gets muted. At a 60s interval this
  # costs about two minutes of delay.
  ALERT_AFTER_CONSECUTIVE_FAILURES = 2

  # A certificate this close to expiry is a problem you still have time to fix.
  # Fourteen days covers even a manual renewal with a purchase in it.
  TLS_EXPIRY_WARNING_DAYS = 14

  scope :ordered, -> { order(position: :asc, name: :asc) }

  def alerting?
    alerted_at.present?
  end

  # ---- TLS certificate ----

  def tls_monitored?
    tls_expires_at.present?
  end

  def tls_expired?
    tls_expires_at.present? && tls_expires_at <= Time.current
  end

  def tls_expiring_soon?
    tls_expires_at.present? && !tls_expired? &&
      tls_expires_at <= TLS_EXPIRY_WARNING_DAYS.days.from_now
  end

  # Whole days remaining, floored: "expires in 0 days" on the last day is more
  # honest than rounding up to 1.
  def tls_days_remaining
    return nil if tls_expires_at.blank?

    ((tls_expires_at - Time.current) / 1.day).floor
  end

  scope :paused, -> { where.not(paused_at: nil) }
  scope :monitored, -> { where(paused_at: nil) }

  def paused?
    paused_at.present?
  end

  # Suspends automatic checks. The last known status is deliberately left
  # untouched so the card still shows the health reading from before the pause
  # rather than resetting to an unknown state.
  def pause!
    update!(paused_at: Time.current)
  end

  def resume!
    update!(paused_at: nil)
  end

  # True when this service has never been checked, or its configured interval
  # has elapsed since the last check. Evaluated in Ruby rather than SQL so the
  # comparison against the per-row interval stays portable across adapters.
  def due_for_check?
    return false if paused?
    return true if last_checked_at.blank?

    last_checked_at <= check_interval_seconds.to_i.seconds.ago
  end

  # Seconds remaining until the next scheduled check; 0 when already due.
  def seconds_until_next_check
    return 0 if paused? || last_checked_at.blank?

    remaining = (last_checked_at + check_interval_seconds.to_i.seconds) - Time.current
    remaining.negative? ? 0 : remaining.round
  end

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
    # Verified by default. Not verifying meant an expired or mismatched
    # certificate passed silently while a browser would refuse the connection —
    # the monitor reporting healthy for a site nobody can reach. The per-service
    # opt-out covers internal endpoints and self-signed certificates.
    http.verify_mode = verify_tls? ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE

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

    # Started explicitly so the peer certificate can be read from the live
    # connection; #request on its own opens and closes it, leaving nothing to
    # inspect.
    http.start
    begin
      response = http.request(request)
      record_certificate!(http.peer_cert) if http.use_ssl?
    ensure
      http.finish if http.started?
    end

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

    evaluate_alerting!(is_success, error_msg)
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

    # A refused connection or a timeout is the most clear-cut failure there is —
    # it must alert like any other.
    evaluate_alerting!(false, e.message)
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

  # Number of checks rendered in the timeline bar. Referenced by the views so
  # the "N checks ago" label cannot drift from the number of bars drawn.
  TIMELINE_BAR_COUNT = 45

  # Timestamp of the oldest check the timeline strip actually shows.
  #
  # The strip is padded with blank bars when there is less history than it can
  # hold, so labelling its left edge "45 checks ago" is wrong until 45 real
  # checks exist. The age of the oldest real check is both accurate from the
  # first check onward and more useful — how far back the strip reaches.
  def oldest_history_check_at
    # pluck.min rather than .minimum(:created_at): an aggregate ignores LIMIT and
    # would return the oldest check in the entire table, including ones that
    # scrolled off the strip long ago.
    check_logs.recent.limit(TIMELINE_BAR_COUNT).pluck(:created_at).min
  end

  def history_bars(count = TIMELINE_BAR_COUNT)
    # Returns last N days/checks status for timeline visualizer
    recent_logs = check_logs.recent.limit(count).to_a.reverse
    if recent_logs.size < count
      pad_count = count - recent_logs.size
      pad_count.times.map { { success: nil, code: nil, latency: 0 } } + recent_logs.map { |l| { success: l.success, code: l.status_code, latency: l.response_time_ms, date: l.created_at } }
    else
      recent_logs.map { |l| { success: l.success, code: l.status_code, latency: l.response_time_ms, date: l.created_at } }
    end
  end

  # Decides whether this check changes anything anyone needs to be told about.
  #
  # Deliberately separate from the check itself: a check records what happened,
  # this decides whether it is news. Counters are written with update_columns to
  # avoid a second Turbo broadcast — perform_check!'s own update! has already
  # refreshed the card.
  def evaluate_alerting!(success, error_message = nil)
    if success
      recover_from_alert! if alerting?
      update_columns(consecutive_failures: 0) if consecutive_failures.positive?
      return
    end

    failures = consecutive_failures + 1
    update_columns(consecutive_failures: failures)

    return if alerting?
    return if failures < ALERT_AFTER_CONSECUTIVE_FAILURES

    raise_alert!(error_message)
  end

  # Records what the handshake already revealed. Cheap: the certificate is a
  # property of a connection we were making anyway.
  def record_certificate!(certificate)
    return if certificate.nil?

    expires_at = certificate.not_after
    issuer = certificate.issuer.to_a.find { |name, _, _| name == "CN" }&.at(1) ||
             certificate.issuer.to_s

    # A changed expiry means a different certificate, so a renewal re-arms the
    # warning rather than staying silent through the next expiry cycle.
    renewed = tls_expires_at.present? && expires_at.present? && tls_expires_at.to_i != expires_at.to_i

    update_columns(
      tls_expires_at: expires_at,
      tls_issuer: issuer.to_s.truncate(120),
      tls_alerted_at: renewed ? nil : tls_alerted_at
    )

    evaluate_tls_alerting!
  rescue StandardError => e
    Rails.logger.warn("Could not record certificate for service #{id}: #{e.class}: #{e.message}")
  end

  # One warning per certificate. Fires once when the window is entered and stays
  # quiet until the certificate is replaced.
  def evaluate_tls_alerting!
    return unless tls_expiring_soon? || tls_expired?
    return if tls_alerted_at.present?
    return unless alertable?

    update_columns(tls_alerted_at: Time.current)
    ServiceAlertJob.perform_later(id, "tls_expiring", nil, nil)
  end

  private

  def raise_alert!(error_message)
    return unless alertable?

    # Recorded before dispatch, so a failure to deliver cannot cause the same
    # alert to be raised again on the next check.
    update_columns(alerted_at: Time.current)
    ServiceAlertJob.perform_later(id, "down", error_message)
  end

  def recover_from_alert!
    downtime_started = alerted_at
    update_columns(alerted_at: nil)

    return unless alertable?

    ServiceAlertJob.perform_later(id, "recovered", nil, downtime_started&.iso8601)
  end

  # An orphaned service has no workspace to notify, and a workspace can turn
  # alerting off entirely.
  def alertable?
    organization.present? && organization.alerts_enabled?
  end

  def determine_new_status(is_success, duration_ms)
    return "outage" unless is_success
    # Only reachable with verification off; with it on the handshake already
    # failed and the check is not a success.
    return "outage" if tls_expired?
    return "degraded" if tls_expiring_soon?
    return "degraded" if duration_ms > 2500 # High latency threshold
    "operational"
  end
end

# Seed initial StatusPulse multi-tenant organization and services.
#
# Development/test seeds a full demo tenant with sample services, synthetic check
# history and an example incident, using well-known credentials.
#
# Production seeds ONLY an organization and one administrator. Demo data is never
# created, and the admin password must be strong: supply SEED_ADMIN_PASSWORD, or
# a random one is generated and printed once. The development password is never
# used in production — it is published in the README.
MIN_ADMIN_PASSWORD_LENGTH = 16

if Rails.env.production?
  admin_email = ENV["SEED_ADMIN_EMAIL"].presence
  raise "SEED_ADMIN_EMAIL must be set when seeding production." if admin_email.nil?

  admin_password = ENV["SEED_ADMIN_PASSWORD"].presence
  generated_password = admin_password.nil?

  if generated_password
    admin_password = SecureRandom.base58(28)
  elsif admin_password.length < MIN_ADMIN_PASSWORD_LENGTH
    raise "SEED_ADMIN_PASSWORD is #{admin_password.length} characters; " \
          "at least #{MIN_ADMIN_PASSWORD_LENGTH} are required in production."
  end

  # Keyed on name, not slug. Keying on slug set it explicitly before validation,
  # which pre-empted Organization#generate_slug's `slug ||=` — so passing only
  # SEED_ORG_NAME produced the right name against a slug of "default", and the
  # public URL did not match the organization. Leaving slug nil lets it derive
  # from the name; SEED_ORG_SLUG still overrides when you want them to differ.
  org = Organization.find_or_create_by!(name: ENV.fetch("SEED_ORG_NAME", "StatusPulse")) do |o|
    o.slug = ENV["SEED_ORG_SLUG"].presence
    o.weekly_digest_enabled = true
  end

  admin = User.find_or_create_by!(email: admin_email) do |u|
    u.name = ENV.fetch("SEED_ADMIN_NAME", "System Administrator")
    u.organization = org
    u.password = admin_password
    u.password_confirmation = admin_password
    u.role = "admin"
  end

  puts "Organization ready: #{org.name} (#{org.slug})"

  if admin.previously_new_record?
    puts "Administrator created: #{admin.email}"
    if generated_password
      puts "\n" + ("=" * 68)
      puts "GENERATED ADMIN PASSWORD (shown once — store it now):"
      puts "  #{admin_password}"
      puts ("=" * 68) + "\n"
    end
  else
    puts "Administrator #{admin.email} already exists; password left unchanged."
  end

  puts "Production seeding complete. No demo data was created."
  # Top-level return stops this file without aborting the surrounding rake
  # process, which `exit` would do mid-db:prepare.
  return
end

puts "Seeding default Organization and Admin user..."

org = Organization.find_or_create_by!(slug: "default") do |o|
  o.name = "Acme Global Infrastructure"
  o.weekly_digest_enabled = true
end

admin = User.find_or_create_by!(email: "admin@statuspulse.local") do |u|
  u.name = "System Administrator"
  u.organization = org
  u.password = "password123"
  u.password_confirmation = "password123"
  u.role = "admin"
end

puts "Default Admin User created: admin@statuspulse.local / password123"

services_data = [
  {
    name: "Core API Gateway",
    description: "Main HTTP API routing service & auth gateway",
    url: "https://httpbin.org/get",
    http_method: "GET",
    headers: "{\n  \"User-Agent\": \"StatusPulse-Agent/2.0\",\n  \"X-Ping-Source\": \"US-East\"\n}",
    expected_status_code: 200,
    check_interval_seconds: 60,
    status: "operational",
    position: 1
  },
  {
    name: "Authentication & Identity Provider",
    description: "OAuth2 & JWT Token issuance endpoint",
    url: "https://httpbin.org/post",
    http_method: "POST",
    headers: "{\n  \"Content-Type\": \"application/json\",\n  \"X-Client-ID\": \"statuspulse-monitor\"\n}",
    request_body: "{\n  \"grant_type\": \"client_credentials\",\n  \"scope\": \"read:status\"\n}",
    expected_status_code: 200,
    check_interval_seconds: 30,
    status: "operational",
    position: 2
  },
  {
    name: "Payment Processing Engine",
    description: "Stripe & Webhook ingestion engine",
    url: "https://httpbin.org/status/200",
    http_method: "GET",
    expected_status_code: 200,
    check_interval_seconds: 60,
    status: "operational",
    position: 3
  },
  {
    name: "CDN & Static Media Edge",
    description: "Global Cloudflare assets & image optimization proxy",
    url: "https://httpbin.org/headers",
    http_method: "GET",
    headers: "Accept: application/json\nCache-Control: no-cache",
    expected_status_code: 200,
    expected_body_match: "headers",
    check_interval_seconds: 120,
    status: "operational",
    position: 4
  },
  {
    name: "Database Replication Secondary",
    description: "Read-replica health check endpoint",
    url: "https://httpbin.org/delay/1",
    http_method: "GET",
    expected_status_code: 200,
    check_interval_seconds: 60,
    status: "degraded",
    position: 5
  }
]

services_data.each do |attrs|
  service = Service.find_or_create_by!(name: attrs[:name]) do |s|
    s.assign_attributes(attrs)
    s.organization = org
  end

  # Create historical check logs for the past 24 hours
  if service.check_logs.empty?
    puts "Generating check logs for #{service.name}..."
    30.times do |i|
      is_success = (service.status != "outage") && (rand > 0.05)
      latency = case service.status
                when "degraded" then rand(2600..4200)
                when "outage" then rand(5000..8000)
                else rand(45..220)
                end

      service.check_logs.create!(
        status_code: is_success ? service.expected_status_code : [500, 502, 504, 0].sample,
        response_time_ms: latency,
        success: is_success,
        error_message: is_success ? nil : "Connection timeout / HTTP 502 Bad Gateway",
        created_at: (30 - i).minutes.ago
      )
    end

    latest = service.check_logs.order(created_at: :desc).first
    service.update_columns(
      last_checked_at: latest.created_at,
      last_response_time_ms: latest.response_time_ms,
      last_status_code: latest.status_code
    )
  end
end

# Seed Sample Active Incident
unless Incident.exists?(title: "Elevated Latency on Secondary Database Replicas")
  puts "Creating sample incident..."
  incident = Incident.create!(
    title: "Elevated Latency on Secondary Database Replicas",
    description: "We are observing increased replication lag and response latency across read replicas in US-East region.",
    severity: "degraded",
    status: "identified",
    organization: org
  )

  db_service = Service.find_by(name: "Database Replication Secondary")
  incident.services << db_service if db_service

  incident.incident_updates.create!(
    status: "identified",
    body: "Root cause isolated to network packet loss on secondary region. Failover to primary replica initiated.",
    created_at: 15.minutes.ago
  )
end

puts "Seeding complete!"

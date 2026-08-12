# ⚡ StatusPulse

> **Real-Time Multi-Tenant Uptime Monitoring, SLA Telemetry & Incident Command Center** built with Ruby on Rails 8.1, Hotwire Turbo Streams, PostgreSQL, and Solid Queue.

---

## 🌟 Key Features

- **🌐 Multi-Tenant Architecture**:
  - Organization-isolated workspaces (`Organization`) with custom vanity public status page URLs (`/status/:org_slug`).
  - Scoped endpoints, incident records, maintenance windows, and user roles (`admin`, `member`).

- **🔐 User Authentication**:
  - BCrypt session authentication protecting telemetry dashboards.
  - Sign-in (`/login`) and Organization Sign-up (`/signup`).

- **📡 Flexible HTTP Health Monitoring**:
  - Full support for **`GET`**, **`POST`**, **`PUT`**, **`HEAD`**, **`PATCH`**, **`DELETE`**, and **`OPTIONS`** methods.
  - Custom HTTP request headers (JSON or `Header: Value` format) for Bearer tokens and API keys.
  - Custom request body payloads for POST/PUT/PATCH checks.
  - Response body pattern matching & configurable request timeouts (default 10s).

- **⚡ Real-Time Hotwire Telemetry**:
  - Live status cards and latency updates using ActionCable & Turbo Streams without refreshing the browser.
  - Visual 90-check timeline bar component for each endpoint.

- **📊 SLA Uptime & P90 Latency Analytics (`/reports`)**:
  - Service-level SLA uptime percentage over 7, 30, and 90 days.
  - Response time percentiles (Average, **P90 latency**).

- **🚨 Incident Command Center (`/incidents`)**:
  - Report and triage degradation or outage incidents (`Investigating`, `Identified`, `Monitoring`, `Resolved`).
  - Timeline progress updates and service association.

- **📧 Scheduled Weekly Email Digest**:
  - Automated weekly SLA digest emails sent to all team members (`WeeklyDigestMailerJob`).
  - Configured with Solid Queue recurring cron (`config/recurring.yml`) to execute every Monday at 8:00 AM.
  - Manual "Dispatch Weekly Email Digest Now" trigger button on the `/reports` page.

---

## 🛠️ Technology Stack

| Component | Technology |
| :--- | :--- |
| **Framework** | Ruby on Rails 8.1 |
| **Language** | Ruby 3.4.1 |
| **Database** | PostgreSQL 16 / SQLite3 (Fallback) |
| **Cache & WebSockets** | Solid Cache & Solid Cable |
| **Background Queue** | Solid Queue |
| **Frontend** | Hotwire (Turbo & Stimulus), Vanilla CSS Dark Theme |
| **Containerization** | Docker & Docker Compose |

---

## 🚀 Quick Start with Docker Compose (Development)

The entire stack (Rails App, PostgreSQL, and Solid Queue Worker) runs out of the box via Docker Compose:

### 1. Launch Containers
```bash
docker compose up -d --build
```

### 2. Prepare & Seed Database
```bash
docker compose exec web bundle exec rails db:prepare db:seed
```

### 3. Open in Browser
- **Dashboard**: [http://localhost:3001](http://localhost:3001)
- **Default Public Status Page**: [http://localhost:3001/status/default](http://localhost:3001/status/default)

> **🔑 Default Seed Credentials**:
> - **Email**: `admin@statuspulse.local`
> - **Password**: `password123`

---

## 💻 Local Development Setup

If you prefer running directly on your host machine:

### 1. Install Dependencies
```bash
bundle install
```

### 2. Prepare & Seed Database
```bash
bin/rails db:prepare db:seed
```

### 3. Start Development Server
```bash
bin/rails server -p 3030
```

Access at `http://localhost:3030`.

---

## 🚢 Production Deployment

For production infrastructure deployments on AWS Lightsail or standalone Ubuntu Linux servers, refer to [DEPLOY.md](DEPLOY.md).

- **Container Topology**: Multi-container Docker Compose setup (`docker-compose.prod.yml`) running `web`, `jobs` (Solid Queue), and `db` (PostgreSQL 16).
- **Web Server Front-End**: High-performance [Thruster](https://github.com/basecamp/thruster) HTTP/2 proxy built into the Rails production container.
- **Host Reverse Proxy**: Host Apache2 reverse-proxies incoming traffic from `https://statuspulse.org` to `127.0.0.1:3000`.
- **TLS / SSL Security**: Let's Encrypt automated TLS certificates managed by Certbot on the host.

---

## 🧪 Running Tests

The test suite covers model unit tests, controller authentication guards, multi-tenant routing, and mailer delivery:

```bash
bundle exec rails test
```

Expected Output:
```
16 runs, 33 assertions, 0 failures, 0 errors, 0 skips
```

---

## 📂 Project Structure

```
├── app/
│   ├── controllers/
│   │   ├── dashboard_controller.rb     # Overview dashboard & telemetry metrics
│   │   ├── services_controller.rb      # Endpoint HTTP check management (CRUD)
│   │   ├── incidents_controller.rb     # Incident command center
│   │   ├── reports_controller.rb       # SLA & P90 latency analytics
│   │   ├── status_page_controller.rb   # Tenant public status pages
│   │   ├── sessions_controller.rb      # Login / Logout authentication
│   │   └── registrations_controller.rb # Account & Organization signup
│   ├── jobs/
│   │   ├── service_check_job.rb        # Background HTTP check execution
│   │   └── weekly_digest_job.rb        # Scheduled weekly mailer job
│   ├── mailers/
│   │   └── weekly_digest_mailer.rb     # SLA summary email compiler
│   ├── models/
│   │   ├── organization.rb             # Multi-tenant boundary
│   │   ├── user.rb                     # BCrypt user model
│   │   ├── service.rb                  # Monitored endpoint & HTTP checker logic
│   │   ├── check_log.rb                # Historical telemetry logs
│   │   ├── incident.rb                 # System outages & degradation records
│   │   └── incident_update.rb          # Incident timeline updates
│   └── views/
│       ├── layouts/application.html.erb # Dark-mode glassmorphic interface
│       └── status_page/show.html.erb   # Public customer status page
├── config/
│   ├── recurring.yml                   # Solid Queue cron schedule
│   └── routes.rb                       # RESTful & vanity tenant routes
├── docker-compose.yml                  # Postgres, Rails Web, Worker dev compose
├── docker-compose.prod.yml             # Production Docker Compose stack
└── Dockerfile                          # Multi-stage Docker production image
```

---

## 📄 License

This project is open-source and available under the [MIT License](LICENSE).

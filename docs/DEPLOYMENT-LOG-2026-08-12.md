# Deployment Log — 12 August 2026

StatusPulse went from a local development repository to a live production
deployment at **https://statuspulse.org** on AWS Lightsail.

19 commits, 70 files changed. Every path below was verified against the running
production instance, not merely deployed.

---

## 1. Domain migration

The `statuspul.se` domain could not be secured; `statuspulse.org` was purchased
instead.

Three classes of string were deliberately treated differently:

| Class | Treatment | Rationale |
| :--- | :--- | :--- |
| **Brand** | `StatusPul.se` → `StatusPulse` | The wordmark no longer contains the domain, so a future domain change touches no UI at all. |
| **Hosts** | `.local` placeholders → `statuspulse.org` | Mailer senders, the outbound monitor `User-Agent`, and the PWA manifest identity. |
| **Infra** | Left unchanged | Container names, the Postgres volume, and the development database name are internal. Renaming a Docker volume orphans its data for no user-visible benefit. |

`module RailsProject1` in `config/application.rb` was **deliberately left alone**.
It is invisible to users, and a partial rename breaks Zeitwerk autoloading and
application boot. Renaming it is an isolated, separately-tested change — not
something to attempt during a deploy.

---

## 2. Production architecture

```
Internet
   │  443 / 80
   ▼
Apache2  (host, apt-installed)
   │  proxies to loopback only
   ├── /cable ──→ ws://127.0.0.1:3000/cable    (mod_proxy_wstunnel)
   └── /      ──→ http://127.0.0.1:3000/
                        │
                        ▼
              Docker Compose (statuspulse)
                 ├── web    Thruster → Puma, published 127.0.0.1:3000:80
                 ├── jobs   Solid Queue supervisor + scheduler
                 └── db     PostgreSQL 16, not published to the host at all
```

- **Instance:** Lightsail, 2 GB RAM / 2 vCPU / 60 GB SSD, 2 GB swap
- **TLS:** Let's Encrypt via certbot's Apache plugin; `www` 301s to apex
- **Secrets:** gitignored `.env` on the server, excluded from the Docker build context
- **Image:** built on the instance
- **Backups:** nightly `pg_dumpall` at 03:17, 14-day retention

**Redis was removed.** No `redis` gem exists in the bundle and nothing references
`REDIS_URL`. Cache, queue, and cable are all Solid adapters on PostgreSQL, so the
Redis container had been running for nothing.

Rails 8 uses **four** databases — `statuspulse_production` plus `_cache`,
`_queue`, and `_cable`. `POSTGRES_DB` creates only the first; the entrypoint's
`db:prepare` creates the rest, which works because the connecting role is the
`postgres` superuser.

---

## 3. Security findings

These were found during the work rather than reported. Listed worst first.

### 3.1 `config/master.key` committed to a public repository

`config/master.key` was committed in the initial commit of a **public** GitHub
repository, alongside `credentials.yml.enc`. `.gitignore` listed the file, but
gitignore has no effect on already-tracked files — so the rule looked like
protection while providing none.

Blast radius was narrow: the credentials file contained **only**
`secret_key_base`; the `smtp:` and `aws:` blocks were still commented-out
scaffolding. Nothing had been deployed.

The danger was forward-looking rather than historical. Rails resolves
`secret_key_base` as `ENV["SECRET_KEY_BASE"] || credentials.secret_key_base`, so
a missing env var would have silently signed production sessions with a public
key. And anything ever added via `credentials:edit` would have been readable by
anyone who cloned the repo.

**Resolved.** Both key and credentials regenerated, verified that the old key no
longer decrypts the new file. History was deliberately **not** rewritten — the
key had been fetchable and forkable for days, so rotation (which renders the
leaked value worthless) is the actual remedy; a force-push would only have broken
the dependabot branches while un-leaking nothing.

### 3.2 Cross-tenant broadcast leak

`turbo_stream_from "services_status"` was a single **global** Turbo Stream. Every
organization subscribed to the same channel and every service broadcast published
to it, so one tenant's service names, URLs, latency, and health status were
pushed live into every other tenant's dashboard.

The controllers scoped correctly by `current_organization`; only the real-time
layer bypassed it. Streams are now keyed per organization.

### 3.3 Fabricated uptime figure

Service cards rendered `99.9% Operational` as a **hardcoded string literal**. It
was not derived from any data, so every service claimed 99.9% uptime regardless
of its real history — including endpoints in full outage. On an uptime
monitoring product this is the worst possible value to fabricate. The public
status page was already computing it correctly; only the internal card lied.

### 3.4 Production seeding created a known admin password

`db/seeds.rb` created `admin@statuspulse.local` / `password123` — a password
documented in the README of a public repository. Seeding production would have
granted immediate administrator access to anyone.

Production now seeds **only** an organization and one administrator: no demo
tenant, no sample services, no example incidents. It requires
`SEED_ADMIN_EMAIL`, rejects passwords under 16 characters, and generates a strong
random one when none is supplied. The development branch is structurally
unreachable when `RAILS_ENV=production`.

### 3.5 Unthrottled authentication

`/login` and `/signup` had no rate limiting whatsoever.

| Endpoint | Key | Limit |
| :--- | :--- | :--- |
| `/login` | normalised email | 5 / minute |
| `/login` | IP | 20 / minute |
| `/signup` | IP | 5 / 10 minutes |

Sign-in is keyed on **email**, not IP: credential stuffing against a single
account is trivially distributed across addresses, and an IP-only limit would
never see it. The per-IP cap catches spraying and is deliberately generous so a
shared office NAT is not locked out.

---

## 4. Bugs that would have broken the deploy

### 4.1 `bin/` was gitignored and untracked

`.gitignore` line 3 was `/bin`, and `git ls-files bin` returned **zero files**.
The Dockerfile depends on it in three places — `./bin/rails assets:precompile`,
`bin/docker-entrypoint`, `bin/thrust`. A clean clone on the server would have
failed at `docker compose build` immediately. `/vendor/*` had the same problem
against `COPY vendor/* ./vendor/`.

### 4.2 ActionCable silently broken behind Apache

Apache evaluates `ProxyPass` during `translate_name` **before** `RewriteRule [P]`,
regardless of their order in the file. The catch-all `ProxyPass /` therefore won
and forwarded `/cable` as ordinary HTTP; ActionCable answers 404 to non-upgrade
requests.

The symptom is the dangerous part: the site loads perfectly and live status cards
simply never update. Fixed with an explicit `ProxyPass /cable ws://…` ahead of the
catch-all. Verified returning `101 Switching Protocols` followed by the
ActionCable welcome and ping frames.

> A debugging note worth remembering: the first WebSocket test returned 404
> because **curl negotiated HTTP/2**, where `Connection: Upgrade` is forbidden and
> silently dropped. Browsers always use HTTP/1.1 for WebSockets. Test with
> `curl --http1.1`.

### 4.3 Health checks never ran

`ServiceCheckJob` existed but nothing scheduled it — `config/recurring.yml`
contained only the weekly digest. Automatic checks had never run; services were
only ever checked by the manual ping button.

The job also ignored `check_interval_seconds`, checking every service on every
invocation. It now sweeps once a minute and checks only services whose own
interval has elapsed, and one unreachable endpoint no longer aborts the sweep for
the rest.

### 4.4 Production database configuration could not connect

`config/database.yml` hardcoded a role `rails_project_1` that did not exist and
read its password from `RAILS_PROJECT_1_DATABASE_PASSWORD`, which was set
nowhere. Worse, the adapter fell back to **sqlite3** whenever `DATABASE_HOST` was
unset — a silent, confusing failure rather than a loud one. The adapter is now
pinned and all four databases derive from `DATABASE_NAME`.

### 4.5 Other build and boot blockers

- `Gemfile.lock` is `BUNDLED WITH 4.0.18`; `ruby:3.4.10-slim` ships Bundler 2.6.x, which refuses that lockfile under `BUNDLE_DEPLOYMENT=1`. Pinned in the Dockerfile.
- `docker-compose.yml`'s jobs command was `bundle exec solid_queue:start` — not a valid command (missing `rake`). That container had never run.
- Overriding the web `command:` defeats `bin/docker-entrypoint`, which only runs `db:prepare` when the final two arguments are exactly `./bin/rails server`. Migrations would never have loaded.
- `.dockerignore` had no `.env` entry, so building on the server would have baked secrets into an image layer.
- `production.rb` had `assume_ssl`, `force_ssl`, and `config.hosts` all commented out, and an **active** `action_mailer` host of `example.com` — every link in the weekly digest pointed at example.com.

---

## 5. Mail

Delivery goes through the **Mailgun HTTP API**, not SMTP. AWS restricts outbound
SMTP on Lightsail/EC2 by default, whereas the API is ordinary HTTPS on 443. It
also returns a message ID that correlates against Mailgun's logs and webhooks —
useful for a product whose job is telling people when things break.

Implemented in `lib/mailgun_api_delivery.rb` with stdlib `Net::HTTP` against the
`/messages.mime` endpoint, sending the MIME document ActionMailer already built.
No gem dependency, no lockfile churn.

One subtlety cost a debugging cycle: `config.action_mailer.mailgun_api_settings=`
in `production.rb` raises `NoMethodError` at boot, because ActionMailer's railtie
applies `config.action_mailer.*` through a load hook registered **before**
`config/initializers` runs — so the accessor does not exist yet. Settings are
registered as `add_delivery_method` defaults instead.

Senders use the display-name form on the verified Mailgun subdomain:
`StatusPulse Reports <reports@mg.statuspulse.org>`. The domain must match
`MAILGUN_DOMAIN` or DKIM/SPF alignment fails.

The weekly digest fires `0 8 * * 1 America/New_York`. Fugit parses the trailing
timezone and tracks DST on its own — 12:00 UTC in summer, 13:00 UTC in winter.

---

## 6. Features added

- **Countdown to next check** — a Stimulus controller on service cards and the detail page. Needs no polling: `perform_check!` calls `update!`, the existing `after_update_commit` broadcast swaps in a fresh card, and the controller reconnects with a new value. Shows `due now` rather than `checking…` at zero, because the sweep runs every 60s and a service can genuinely wait that long past its interval.
- **Pause / resume monitoring** — a nullable `paused_at` keeps monitoring state separate from health status, so pausing preserves the last known reading and a manual ping cannot silently un-pause. Paused services write no check logs, so paused windows are excluded from SLA automatically. Amber badge, not red: pausing is a deliberate operator action and must not read as an outage.
- **Live create and destroy** — the model only had `after_update_commit`, so new services required a page refresh and deleted ones stayed on screen. Creates now prepend to the top of the list.
- **Real favicon** — the app shipped the Rails scaffold placeholder (a red circle) and neither layout carried favicon link tags at all. Now the brand pulse mark on the indigo→cyan tile: SVG, 512 PNG, apple-touch-icon, multi-resolution `.ico`. The PWA manifest was also routed, having shipped as a view that was never reachable.
- **Honest timeline labels** — `90 checks ago` described the width of the chart while drawing 45 bars, and was wrong for every service until it accumulated a full strip, since `history_bars` pads with blanks. The label now shows how far back the strip actually reaches.

---

## 7. Verified in production

- `https://statuspulse.org/up` → 200; `www` → 301 to apex
- `/cable` → `101 Switching Protocols` + ActionCable welcome and ping frames
- All four PostgreSQL databases created
- Containers bound to `127.0.0.1` only; Postgres not published to the host
- Recurring sweep running, honouring per-service intervals (548 ms when checking, 5 ms when skipping)
- Weekly digest delivered to a real inbox via the Mailgun API
- `pg_dumpall` producing a non-empty archive, cron installed
- Countdown, pause, live-create, and favicon all confirmed in the browser
- 48 tests, 122 assertions, 0 failures

---

## 8. Outstanding

Nothing blocking. In rough priority order:

1. **Backup restores are untested.** A backup you have never restored is a hypothesis. Worth doing a `pg_restore` into a scratch database once.
2. **Backups are on the same instance.** A lost instance loses both the app and its backups. Consider shipping the dumps to S3.
3. **`config.time_zone` is unset**, so timestamps render in UTC throughout the UI even though the digest now fires Eastern.
4. **`certbot` added a duplicate http→https rewrite** to the vhost. Harmless — first match wins — but cosmetically untidy.
5. **No Apache-layer rate limiting** (`mod_evasive`). The Rails limits handle targeted abuse; this would only add coverage for crude volumetric floods, and is easy to misconfigure into locking out real users.
6. **Placeholder error pages.** `public/4xx.html` and `500.html` are stock and unbranded.
7. **CSP is entirely disabled** — `content_security_policy.rb` is fully commented out while both layouts emit `csp_meta_tag`. If enabled later, `wss://statuspulse.org` must be in `connect_src` or ActionCable breaks.

---

## 9. Commits

```
38a9db4  fix(build)     track bin/ and vendor so the production image can build
ae746ee  fix(docker)    pin Bundler to the lockfile version and drop the test group
605f2a2  feat           rebrand to StatusPulse and move to statuspulse.org
e70a522  feat(config)   make the production environment deployable
fa20c0a  feat(mail)     deliver via the Mailgun HTTP API instead of SMTP
00772d5  feat(security) never seed demo credentials into production
3074f65  feat(deploy)   production compose stack, Apache vhost and runbook
4b1df7b  feat(mail)     make sender addresses configurable via MAIL_FROM
3bb0a9f  fix            actually schedule recurring service health checks
1921315  fix(apache)    proxy /cable explicitly so WebSockets actually tunnel
83582f0  feat           show a countdown to each service's next health check
377e1aa  fix(security)  scope service broadcasts per organization; add pause/resume
a70dcce  feat           real favicon and app icons
649c145  feat           surface paused state in the service list and detail page
fb7531d  fix            stop displaying a hardcoded 99.9% uptime on service cards
620e913  feat(mail)     use display-name senders on the Mailgun subdomain
fee8d60  chore(security) rotate the exposed master key; digest at 08:00 Eastern
e77fa4a  fix            label the timeline by how far back it reaches, not bar count
7b3185b  feat(security) rate limit sign-in and sign-up
```

Operational procedures live in [`DEPLOY.md`](../DEPLOY.md).

---

## 10. After the deployment — same day

### Public landing page

The site had no marketing surface: `root` required a sign-in, so an anonymous
visitor — and any crawler — received a login form. Nothing described what the
product is.

Positioned on **multi-tenancy and the MSP shape** rather than generic uptime
monitoring. Competing head-on for "uptime monitoring" against incumbents with a
decade of domain authority is not winnable; isolated workspaces and per-client
status pages are a narrower position that is. The status pages are also the real
SEO asset: nobody picks the 40th result for "uptime monitoring", but people do
search a client's brand name during an outage.

Design direction is **"instrument"** — a graticule grid, hairline rules,
calibration ticks and tabular numerals. The first attempt was rejected as
generic, correctly: it had blurred radial gradients, gradient-filled headline
text, glassy rounded cards and an indigo→cyan palette, which is the house style
of every developer-tool landing page of the last three years.

The governing rule is **colour is reserved for signal**. The page is monochrome
ink on near-black; the only saturated colour anywhere is green/amber/red where
it means operational/degraded/outage. An operations product that spends colour
on decoration advertises the opposite of the discipline it sells.

The hero *shows* multi-tenancy rather than asserting it: several client
workspaces checked in parallel, one degrading into an incident and recovering. A
continuous uptime rail runs the page's full height as its spine. Both respect
`prefers-reduced-motion`. Sample workspaces are fictional and labelled as such —
no invented customers, testimonials or metrics.

### Application rebranded to match

The same palette, radii and typography now apply to the dashboard. The rule
matters more here than on the landing page: the app spent indigo and cyan on
chrome — brand chip, wordmark, primary buttons, focus rings, background washes —
which competed with the status colours that carry meaning. Removing that
competition makes a degraded service *more* visible.

Uppercase was deliberately **not** carried over except on short labels. It suits
a page read once; it is tiring on a dashboard watched all day.

### SEO plumbing

- `sitemap.xml` rendered dynamically, so opted-in client status pages appear automatically
- `robots.txt` with a `Sitemap:` directive and the application paths disallowed
- Canonical tags on the marketing and status layouts
- Explicit `noindex` on signed-in pages — a robots.txt disallow is a request not to crawl, and does not prevent indexing of a URL discovered elsewhere
- `Organization#status_page_indexable`, **default true**: status pages are meant to be found; tenants can opt out

### Additional findings

- **Sitemap was behind authentication.** `SitemapsController` inherited `require_login`, so Googlebot would have been redirected to `/login`. Caught by a test, not by inspection.
- **Orphaned services are monitored but invisible.** `Service belongs_to :organization, optional: true` permits `organization_id: nil`. Such services are excluded from every tenant-scoped view but are still checked by `ServiceCheckJob`, which sweeps with an unscoped `find_each`. Five seeded development services were in this state. Worth deciding whether the association should be required.
- **`/reports` rendered the digest setting in the operational green**, though a setting being enabled is not a service state, and still claimed 8 AM after the schedule moved to Eastern. Both fixed.

### Commits

```
ed7a199  feat           public landing page positioned on multi-tenancy
b0e687e  feat           rebrand the application to the instrument theme
9d43a47  feat(seo)      sitemap, robots, canonicals and per-tenant indexing control
```

### Still outstanding

Everything in section 8, plus:

- **Landing and rebrand are not yet deployed.** They are pushed to `master`; the instance still runs the pre-landing build. `git pull && docker compose -f docker-compose.prod.yml up -d --build`, then `bin/rails db:migrate` for `status_page_indexable`.
- **No per-tenant UI for the indexing opt-out.** The column exists and is respected, but nothing in the interface toggles it yet.
- **Search Console has not been submitted.** Worth doing once the landing page is live, not before — otherwise the first crawl records a login form.

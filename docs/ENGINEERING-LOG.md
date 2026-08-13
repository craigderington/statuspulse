# Engineering log — 12–13 August 2026

StatusPulse went from a local repository on a domain that could not be secured
to a live, TLS-terminated, multi-tenant product with mandatory two-factor
authentication, offsite backups, failure alerting and certificate monitoring.

**38 commits. 143 files changed. 162 tests, 524 assertions.**

Provisioning specifics are in [`DEPLOY.md`](../DEPLOY.md); the day-one
deployment narrative is in
[`DEPLOYMENT-LOG-2026-08-12.md`](DEPLOYMENT-LOG-2026-08-12.md). This document is
the record of what was found, what was decided, and why.

---

## 1. The security findings

Nine defects were found that were not on any list when the work started. They
are recorded first because they are the most useful thing here.

### Authentication bypasses (three, all in code written during this work)

Every one was exploitable against an account that already had 2FA enabled,
using **nothing but its password**.

1. **Existing TOTP secret disclosed.** `GET /two-factor/setup` rendered the
   enrolment page for any pending user, including one already enrolled. Since a
   secret was generated only when absent, the page displayed the victim's
   *existing* secret and QR. An attacker with the password could scan it and
   answer the challenge. — `334444a`
2. **Unconditional authentication.** `POST /two-factor/recovery-codes` called
   `complete_authentication` for any pending session. One request, no code, no
   secret. Not in the report that flagged (1); it surfaced while writing the
   test for it, and was the more severe of the two. — `334444a`
3. **Grafted session identity.** Signup set `session[:user_id]` without
   `reset_session`, making it the one way to hold a signed-in and a pending
   identity at once. Combined with recovery codes stored as an identity-less
   array, codes minted while acting as one account authenticated another.
   Reproduced end to end before fixing. — `27e89f3`

**The pattern**: two of the three were the same shape — *state trusted as proof
without being bound to the identity it proves something about*. The session
helpers now own that binding so individual actions cannot get it wrong.

### Tenant isolation (three)

4. **Global Turbo Stream.** `turbo_stream_from "services_status"` was a single
   channel shared by every organization, so one tenant's service names, URLs,
   latency and status were broadcast live to every other tenant's dashboard. —
   `377e1aa`
5. **Anonymous requests assigned tenant #1.** `Current.organization ||=
   Organization.first` handed every unauthenticated visitor whichever
   organization was row #1, and bare `/status` inherited it. — `81d1152`
6. **Unscoped fallback on the public status page.** `StatusPageController`
   degraded to `Service.ordered` — every service across every tenant — when no
   organization resolved. Unreachable only because (5) masked it, so fixing (5)
   alone would have *opened* it. — `81d1152`

Same shape again: scoping enforced on the path people read, absent from the
fallback.

### Credentials and honesty (three)

7. **`config/master.key` committed to a public repository.** Present since the
   initial commit, alongside `credentials.yml.enc`. Blast radius was narrow —
   the file held only `secret_key_base` — but the danger was forward-looking:
   Rails falls back to the credentials value whenever `SECRET_KEY_BASE` is
   unset, and anything later added via `credentials:edit` would have been
   readable by anyone who cloned the repo. Rotated rather than history-rewritten:
   the key had been fetchable for days, so rotation is what actually neutralises
   it. — `fee8d60`
8. **Fabricated uptime.** Service cards rendered `99.9% Operational` as a
   hardcoded string. Every service claimed 99.9% regardless of history,
   including ones in outage. On an uptime monitor this is the worst possible
   value to invent. — `fb7531d`
9. **Certificates never validated.** `verify_mode = VERIFY_NONE`, so an expired
   or mismatched certificate passed silently while a browser would refuse the
   connection — the monitor reporting *operational* for a site nobody can reach.
   — `971f75a`

### Two more worth naming

- **Unthrottled authentication.** `/login` and `/signup` had no rate limiting at
  all. Sign-in is now keyed on the **email**, not the IP: credential stuffing
  against one account is trivially distributed across addresses, and an IP-only
  limit would never see it. — `7b3185b`
- **The admin role was decorative.** A `role` column with no validation and no
  enforcement anywhere; a member could do everything an admin could. — `44c73c1`

---

## 2. Deploy blockers found before they bit

- **`bin/` was gitignored and untracked** — zero files in git, while the
  Dockerfile depends on it in three places. A clean clone on the server would
  have failed at `docker compose build` immediately. Same for `vendor/`. —
  `38a9db4`
- **`config/database.yml` could not connect in production** — a hardcoded role
  that did not exist, a password from an env var set nowhere, and a silent
  fallback to **sqlite3** when `DATABASE_HOST` was unset. — `e70a522`
- **The jobs container had never run** — `bundle exec solid_queue:start` is not
  a valid command; it is missing `rake`. — `3074f65`
- **Health checks never ran.** `ServiceCheckJob` existed but nothing scheduled
  it, and it ignored `check_interval_seconds` entirely. — `3bb0a9f`
- **Bundler 4 lockfile against a Bundler 2 image**, which refuses to install
  under `BUNDLE_DEPLOYMENT=1`. — `ae746ee`

---

## 3. What shipped

**Platform.** Rebranded to StatusPulse on `statuspulse.org`; Let's Encrypt TLS
behind host Apache2; Docker Compose on Lightsail; four Rails 8 databases;
Mailgun HTTP API for mail; nightly backups to S3.

**Security.** Mandatory TOTP with recovery codes; rate limiting on sign-in,
sign-up, 2FA verification and recovery-code regeneration; per-tenant broadcast
scoping; write-only offsite backup credentials.

**Monitoring.** Recurring checks honouring per-service intervals; failure
alerting by email and signed webhook; TLS certificate verification and expiry
warnings; pause/resume; check-history pagination; 90-day retention.

**Interfaces.** Public landing page; the "instrument" design language applied
across the app; account menu; workspace settings; alerts & email settings;
personal security page; real favicon and app icons.

**SEO.** Dynamic sitemap, `robots.txt`, canonicals, `noindex` on signed-in
pages, per-tenant indexing opt-out.

---

## 4. Design decisions worth remembering

**Colour is reserved for signal.** The interface is monochrome ink on
near-black; the only saturated colour is green/amber/red where it means
operational/degraded/outage. This matters more in the app than on the landing
page: indigo and cyan chrome used to compete with the status colours that carry
meaning, which is what makes a dashboard hard to read at a glance.

**Alert after two consecutive failures, not one.** A single failed check is
usually a blip. Alerting on every one is how alerting gets muted, and a muted
alert is worse than none. One message when it breaks, one when it recovers,
never one per failed check.

**Backup credentials are write-only.** The instance can `PutObject` and nothing
else — it cannot list, read, or delete. A compromised server can neither
exfiltrate the backup history nor destroy it. Expiry is a bucket lifecycle rule,
so nothing on the server can remove an offsite copy.

**`session[:user_id]` means fully authenticated.** A password proved but not yet
seconded lives in a separate pending key, so every existing `require_login`
check stayed correct unmodified. Getting this wrong is how 2FA becomes
decorative.

**Reports are clamped to the retention window.** Once purging began, an
unbounded `?days=` would have computed uptime from whatever survived —
flattered by exactly the failures that were deleted. The page says which window
it is actually showing.

**Certificate expiry is observed, not checked separately.** Every HTTPS request
already completes a TLS handshake, so the certificate is in hand. No new check
type, no extra request, every existing HTTPS service covered with no
configuration.

**Encryption keys are not derived from `SECRET_KEY_BASE`.** Rotating that —
which happened once during this work — would otherwise make every stored TOTP
secret undecryptable and lock out every user with no obvious cause.

---

## 5. Bugs introduced during this work, and caught

Recorded because the pattern is more useful than the individual fixes.

- **Archive verification rejected valid backups.** `gunzip | grep -q` under
  `set -o pipefail`: grep exits at the first match, gunzip dies of SIGPIPE, and
  the pipeline reports 141. The header is on line 2, so the *more valid* the
  archive the faster it "failed" — and a corrupt one would have passed. Exactly
  backwards. — `6234d4e`
- **Encryption keys demanded during asset precompile.** The initializer keyed
  off `Rails.env.production?` alone, but `assets:precompile` runs at build time
  in production mode with no secrets — which is what `SECRET_KEY_BASE_DUMMY`
  signals. Broke the image build. — `03e83ea`
- **DNS resolution inside a model validation.** An unreachable webhook host
  would have blocked saving unrelated settings, including *turning alerts off*.
  Syntax and literal-IP checks now happen at the form; resolution at delivery.
  — `6508a63`
- **Rate limiting throttled the test suite's own logins.** Counters live in
  `Rails.cache`, shared across a worker process, so the sixth sign-in of the
  same user in a minute got throttled and later tests redirected to `/login`.
  It surfaced as "pagination is broken". — `e604710`

---

## 6. Verified, and not

**Verified against production:** TLS and the `www` redirect; ActionCable
returning `101` through Apache; all four databases; containers bound to
loopback; the recurring sweep honouring per-service intervals; a weekly digest
delivered to a real inbox via Mailgun; a backup restored into an isolated
cluster with matching row counts; the offsite upload; 2FA enrolment and
challenge end to end; certificate capture through the real check path.

**Not yet verified:**

- **Alert delivery has never actually sent.** The trigger logic is well covered
  by tests, but `ServiceAlertMailer` has not been exercised against real
  Mailgun. Pointing a throwaway service at `https://httpbin.org/status/500`
  would alert in about two minutes.
- **Webhook delivery has never reached a real endpoint.** Signing and SSRF
  refusal are tested; an actual POST has not been made.
- **The verified restore predates the 2FA tables.** If the `AR_ENCRYPTION_*`
  keys are lost, encrypted secrets restore as unreadable.
- **The S3 copy has never been restored *from*** — only the local archive has.

---

## 7. Outstanding

Tracked in [`BACKLOG.md`](BACKLOG.md). The two largest are both about proving
recovery rather than adding features: restore a backup containing the 2FA
tables, and restore from S3 rather than from disk. After that, orphaned services
(`Service belongs_to :organization, optional: true` still permits
`organization_id: nil` — monitored, invisible, unscoped) is the last member of
the tenancy-bug family found during this work.

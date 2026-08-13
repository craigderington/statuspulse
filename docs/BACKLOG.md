# Backlog

Things worth doing, roughly in the order I'd do them. Written down so they stop
living in conversation.

---

## 1. Alert on failure

**StatusPulse currently tells nobody when something breaks.**

`Service#perform_check!` updates the status, writes a check log, and broadcasts
to the dashboard. There is no email, no webhook, no notification of any kind.
The only outbound mail in the entire app is the Monday digest. A client's API can
go down at 02:00 and the first anyone hears of it is 08:00 the following Monday
— unless somebody happens to be watching the dashboard at the time.

For an uptime monitoring product this is the central feature, not an
enhancement. Everything else in this list is secondary to it.

Design questions to settle first:

- **Who is told?** Everyone in the workspace, or a per-service list? Agencies
  will want per-client routing.
- **When?** Immediately on the first failure, or after N consecutive failures?
  Alerting on a single blip is how alerting gets muted and stops working.
- **How often?** One alert per incident, or repeated until resolved? Both are
  defensible; silence after the first is a common regret.
- **Recovery?** An alert that never says "it's back" trains people to ignore it.
- **Channels?** Email exists already. Webhooks and Slack are the usual next
  requests, and are what an MSP will actually route into their on-call.

Note that the existing `Incident` model already has the vocabulary
(investigating / identified / monitoring / resolved) and could plausibly be
opened automatically on a sustained failure rather than inventing a parallel
concept.

## 2. More check types

Currently every check is an HTTP request. Worth adding:

- **TLS certificate expiry** — arguably the highest-value addition after
  alerting, because it is the outage everyone sees coming and still gets hit by.
  Would warn at a configurable threshold (30/14/7 days) rather than only failing
  once expired. Note this needs a different failure model: a certificate 20 days
  from expiry is not "down", so it does not fit the operational / degraded /
  outage states cleanly. Probably a separate check type with its own severity.
- **Domain expiry** — same shape, via WHOIS/RDAP. Same cause of embarrassing,
  entirely preventable outages.
- **DNS resolution** — a record resolving to an expected value.
- **TCP port** — for services that are not HTTP at all.
- **Keyword absence** — assert a string is *not* present. Useful for catching a
  page that returns 200 while rendering a stack trace.

## 3. Restore a backup containing the 2FA tables

The verified restore predates `users.totp_secret` and `recovery_codes`. If the
`AR_ENCRYPTION_*` keys are ever lost or rotated, encrypted secrets restore as
unreadable and every user is locked out with no obvious cause. Worth proving the
round trip, including that the keys are backed up somewhere other than the
server.

Procedure is in `docs/BACKUPS.md`; it has only ever been run against a
pre-2FA dump.

## 4. Restore *from S3*, not just locally

The verified restore used a local archive. The S3 copy — the one that matters if
the instance is lost — has never been restored from. Different failure modes:
wrong region, object never actually uploaded, lifecycle rule having quietly
expired something.

## 5. Orphaned services

`Service belongs_to :organization, optional: true` permits
`organization_id: nil`. Such services are excluded from every tenant-scoped view
but are still checked by `ServiceCheckJob`, which sweeps unscoped — monitored,
invisible, and unattributable. Five development services were in this state.

Making the association required needs a backfill and a check of anything relying
on nil. It is the same family as the three tenancy bugs already fixed.

## 6. Smaller things

- **`/reports` P90 is computed in Ruby** by loading every latency into memory
  and sorting. Fine at current volume; it loads 30 days of rows per service per
  page load. A SQL percentile would be cheaper.
- **Public error pages** (`public/404.html`, `500.html`) are stock and
  unbranded.
- **CSP is entirely disabled** — `content_security_policy.rb` is fully commented
  out while both layouts emit `csp_meta_tag`. If enabled, `wss://statuspulse.org`
  must be in `connect_src` or ActionCable breaks.
- **No UI for adding teammates.** Users can only be created by signing up, which
  creates a new organization each time — so there is currently no way to add a
  second person to an existing workspace.
- **`module RailsProject1`** in `config/application.rb`. Deliberately left:
  user-invisible, and a partial rename breaks Zeitwerk and boot.

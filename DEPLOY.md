# StatusPulse production deployment

This runbook provisions a fresh Ubuntu Lightsail instance for the following topology:

- Apache runs on the host and is the only process listening publicly on ports 80/443.
- Puma runs in Docker and is published only as `127.0.0.1:3000`.
- PostgreSQL and any other backing services stay on private Docker networks.
- `statuspulse.org` is canonical; `www.statuspulse.org` permanently redirects to it.

Commands assume an Ubuntu sudo-capable operator, the repository at `/opt/statuspulse`, and the production Compose file `docker-compose.prod.yml`. Review that file before deploying: the commands below call the Rails service `web` and the PostgreSQL service `db`. If `docker compose -f docker-compose.prod.yml config --services` reports different names, substitute the actual names consistently.

## 1. Reserve the static IP and restrict the Lightsail firewall

In the AWS Lightsail console:

1. Create and attach a **static IP** to the instance. Do not publish DNS against the instance's replaceable dynamic IP.
2. Under **Networking -> IPv4 firewall**, retain only:
   - TCP 22 (SSH; restrict source addresses if operationally possible)
   - TCP 80 (HTTP and Let's Encrypt HTTP-01)
   - TCP 443 (HTTPS)
3. Remove broad rules and application/database ports such as 3000, 5432, and 6379.
4. Apply equivalent IPv6 restrictions if IPv6 is enabled.

Later, verify that Compose publishes Puma as `127.0.0.1:3000`, never `0.0.0.0:3000`.

## 2. Create 2 GB of swap before installing or building

The target has 2 GB RAM, 2 vCPU, and a 60 GB SSD. Two GB is sufficient for runtime and builds, but native gem compilation (`pg`, `nokogiri`, and `bcrypt`) can spike while PostgreSQL is resident. Create swap now as a safety net rather than waiting for an out-of-memory failure.

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
printf '/swapfile none swap sw 0 0\n' | sudo tee -a /etc/fstab
printf 'vm.swappiness=10\n' | sudo tee /etc/sysctl.d/99-statuspulse-swap.conf
sudo sysctl --system
swapon --show
free -h
```

If `fallocate` is unsupported on the filesystem, replace only its line with:

```bash
sudo dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress
```

With two CPUs, a host-side Bundler diagnostic/install may use `bundle install -j2`; do not use more jobs on this instance. The production Dockerfile normally installs gems inside the image build, so let Compose build the image unless debugging the bundle directly.

The 60 GB disk is ample, but old image layers accumulate. The routine update procedure below prunes unused Docker objects older than seven days.

## 3. Patch Ubuntu and install Docker Engine, Compose, Apache, and certbot

Install Docker from Docker's official apt repository rather than Ubuntu's legacy `docker.io` package:

```bash
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y ca-certificates curl gnupg apache2 ssl-cert certbot python3-certbot-apache

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
printf '%s\n' \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu" \
  "${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker apache2
```

Optionally grant the deployment account Docker access, then start a fresh login session before relying on it:

```bash
sudo usermod -aG docker "$USER"
```

Enable every Apache module used by the supplied virtual host:

```bash
sudo a2enmod proxy proxy_http proxy_wstunnel ssl headers rewrite remoteip deflate http2
sudo systemctl restart apache2
apache2ctl -M | grep -E 'proxy|proxy_http|proxy_wstunnel|ssl|headers|rewrite|remoteip|deflate|http2'
docker version
docker compose version
```

## 4. Publish DNS and wait for propagation

At the authoritative DNS provider, create:

| Type | Name | Value |
| --- | --- | --- |
| A | `@` | Lightsail static IPv4 address |
| A | `www` | Lightsail static IPv4 address |

If IPv6 is not configured on the instance, remove stale AAAA records. A client may otherwise reach the wrong machine over IPv6.

Verify both names from more than one resolver before requesting certificates:

```bash
dig +short A statuspulse.org @1.1.1.1
dig +short A www.statuspulse.org @1.1.1.1
dig +short A statuspulse.org @8.8.8.8
dig +short A www.statuspulse.org @8.8.8.8
```

Both names must resolve to the attached static IP. Certbot's HTTP-01 challenge cannot succeed until public DNS is live and port 80 reaches this host.

## 5. Check out the application and create the production environment

```bash
sudo install -d -o "$USER" -g "$USER" /opt/statuspulse
# Use the repository's real clone URL here.
git clone <REPOSITORY_URL> /opt/statuspulse
cd /opt/statuspulse
docker compose -f docker-compose.prod.yml config --services
```

Create `/opt/statuspulse/.env` with restrictive permissions. Start from the repository's template, then replace every placeholder; do not copy development credentials. Compose supplies `STATUSPULSE_DATABASE_PASSWORD` to Rails from `POSTGRES_PASSWORD`, and the current Rails database configuration uses four production databases (primary, cache, queue, and cable).

```bash
umask 077
install -m 600 .env.example .env
${EDITOR:-vi} .env
```

At minimum, replace the template values for these settings (and fill in its Mailgun settings if email delivery is required):

```dotenv
RAILS_ENV=production
DOMAIN_NAME=statuspulse.org
SECRET_KEY_BASE=<output of openssl rand -hex 64>
POSTGRES_PASSWORD=<output of openssl rand -hex 32>
DATABASE_NAME=statuspulse_production
```

`docker-compose.prod.yml` currently fixes the PostgreSQL role as `postgres` and passes the password above to Rails; do not add a conflicting `POSTGRES_USER`. `DATABASE_NAME` controls the Rails production database names (`statuspulse_production`, plus `_cache`, `_queue`, and `_cable`). Never commit `.env` or secret key material. Generate random values with a password manager or the commands shown above. Confirm the rendered Compose configuration without printing it into logs or tickets:

```bash
docker compose -f docker-compose.prod.yml config --services
```

Also confirm the rendered `web` port binding in the Compose file is exactly loopback-only (`127.0.0.1:3000:...`). The container's internal port may differ (for example, 80); the host-side address and port must still be `127.0.0.1:3000` for Apache.

## 6. Install and validate the Apache virtual host

The configuration uses Ubuntu's snake-oil certificate only to make the initial TLS vhost valid. Certbot replaces those bootstrap paths with its managed Let's Encrypt certificate paths.

```bash
cd /opt/statuspulse
sudo install -d -m 0750 -o root -g adm /var/log/apache2/statuspulse
sudo install -m 0644 deploy/apache/statuspulse.org.conf /etc/apache2/sites-available/statuspulse.org.conf
sudo a2dissite 000-default.conf default-ssl.conf 2>/dev/null || true
sudo a2ensite statuspulse.org.conf
sudo apache2ctl configtest
sudo systemctl reload apache2
```

The expected configtest result is `Syntax OK`. Before cert issuance, verify the ACME exception is not redirected while normal HTTP is:

```bash
curl -I http://statuspulse.org/
curl -i http://statuspulse.org/.well-known/acme-challenge/nonexistent
```

The first response must be a 301 to `https://statuspulse.org/...`; the challenge request may be 404 but must not redirect to HTTPS.

The vhost also rejects WordPress, PHP, and PHP-administration scanner paths at
Apache rather than forwarding them to Rails. Verify both cleartext and TLS
behavior after installing or changing the vhost:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' http://statuspulse.org/wp-admin/
curl -sS -o /dev/null -w '%{http_code}\n' https://statuspulse.org/wp-login.php
curl -sS -o /dev/null -w '%{http_code}\n' https://statuspulse.org/index.PHP
curl -sS -o /dev/null -w '%{http_code}\n' https://statuspulse.org/phpmyadmin/
curl -sS -o /dev/null -w '%{http_code}\n' https://statuspulse.org/wp-json/
curl -sS -o /dev/null -w '%{http_code}\n' https://www.statuspulse.org/xmlrpc.php
```

Every command must print `404`. A normal unknown Rails path should also remain
404, while ordinary HTTP application paths must continue to return the canonical
301 and ACME challenge paths must remain exempt from that redirect.

## 7. Obtain and test the Let's Encrypt certificate

Request one certificate covering both the canonical and redirect hostnames:

```bash
sudo certbot --apache \
  --cert-name statuspulse.org \
  -d statuspulse.org \
  -d www.statuspulse.org \
  --redirect
sudo apache2ctl configtest
sudo systemctl reload apache2
sudo certbot renew --dry-run
```

If certbot offers redirect choices, retain the vhost's existing permanent redirect behavior. Inspect the resulting site file and confirm its certificate directives point under `/etc/letsencrypt/live/statuspulse.org/`:

```bash
sudo grep -E 'SSLCertificate(File|KeyFile)' /etc/apache2/sites-enabled/statuspulse.org.conf
```

Certbot installs its renewal timer automatically:

```bash
systemctl list-timers | grep certbot
```

## 8. First boot, database preparation, and seed

Start backing services and build the application image:

```bash
cd /opt/statuspulse
docker compose -f docker-compose.prod.yml up -d --build
docker compose -f docker-compose.prod.yml ps
```

Prepare all four Rails production databases (primary, cache, queue, cable):

```bash
docker compose -f docker-compose.prod.yml exec -T web bin/rails db:prepare
```

Then seed the administrator. In production the seed creates **only** an organization
and one admin — never the demo tenant, sample services, or example incidents that
development seeding produces:

```bash
docker compose -f docker-compose.prod.yml exec -T \
  -e SEED_ADMIN_EMAIL='you@statuspulse.org' \
  -e SEED_ADMIN_PASSWORD='<a long, random password>' \
  web bin/rails db:seed
```

The seed refuses to run without `SEED_ADMIN_EMAIL`, and rejects any
`SEED_ADMIN_PASSWORD` shorter than 16 characters. Omit `SEED_ADMIN_PASSWORD`
entirely and it generates a strong random one and prints it **once** — capture it
from the output before you lose the terminal buffer.

Optional overrides: `SEED_ORG_NAME`, `SEED_ORG_SLUG`, `SEED_ADMIN_NAME`.

Re-running the seed is safe: it will not reset the password of an existing admin.

**Note:** the development seed's well-known credentials (`admin@statuspulse.local` /
`password123`, documented in the README) are unreachable in production — that branch
of `db/seeds.rb` does not execute when `RAILS_ENV=production`.

Confirm Puma is only loopback-bound and the health endpoint works through both layers:

```bash
sudo ss -ltnp | grep -E ':(80|443|3000)\b'
curl --fail --show-error http://127.0.0.1:3000/up
curl --fail --show-error https://statuspulse.org/up
curl -I https://www.statuspulse.org/some/path?probe=1
```

Expected results:

- Port 3000 shows `127.0.0.1:3000`, not `0.0.0.0:3000` or `[::]:3000`.
- Both `/up` requests succeed.
- `www` returns one 301 whose `Location` is `https://statuspulse.org/some/path?probe=1`.

## 9. Configure dated PostgreSQL backups with rotation

Create a root-owned backup directory:

```bash
sudo install -d -m 0700 -o root -g root /var/backups/statuspulse
```

Edit root's crontab with `sudo crontab -e` and add this single line (daily at 02:15 UTC):

```cron
15 2 * * * cd /opt/statuspulse && umask 077 && stamp=$(date +\%F_\%H\%M\%S) && /usr/bin/docker compose -f docker-compose.prod.yml exec -T db pg_dump -U postgres -d statuspulse_production --format=custom --no-owner --no-acl > "/var/backups/statuspulse/statuspulse_${stamp}.dump.tmp" && mv "/var/backups/statuspulse/statuspulse_${stamp}.dump.tmp" "/var/backups/statuspulse/statuspulse_${stamp}.dump" && find /var/backups/statuspulse -type f -name 'statuspulse_*.dump' -mtime +14 -delete
```

This writes the primary Rails database in custom format atomically and retains 14 days. Solid Cache, Queue, and Cable are operational stores and are rebuilt/migrated by Rails; if policy requires their transient contents, add equivalent dumps for the `_cache`, `_queue`, and `_cable` databases. If you changed `DATABASE_NAME`, substitute that primary name in both cron commands. Test the exact cron command manually once, then inspect and validate the dump:

```bash
sudo sh -c 'cd /opt/statuspulse && umask 077 && stamp=$(date +%F_%H%M%S) && /usr/bin/docker compose -f docker-compose.prod.yml exec -T db pg_dump -U postgres -d statuspulse_production --format=custom --no-owner --no-acl > "/var/backups/statuspulse/statuspulse_${stamp}.dump"'
sudo ls -lh /var/backups/statuspulse
latest=$(sudo find /var/backups/statuspulse -type f -name 'statuspulse_*.dump' -printf '%T@ %p\n' | sort -nr | head -1 | cut -d' ' -f2-)
sudo docker compose -f /opt/statuspulse/docker-compose.prod.yml exec -T db pg_restore --list < "$latest" | head
```

A local backup on the same Lightsail disk is not disaster recovery. Copy encrypted dumps to a separate account or object store and regularly rehearse a restore to a disposable database.

## 10. Routine update loop

Take a backup before risky releases. Then update, rebuild, migrate, and restart:

```bash
cd /opt/statuspulse
git pull --ff-only
docker compose -f docker-compose.prod.yml build
docker compose -f docker-compose.prod.yml run --rm web bin/rails db:prepare
docker compose -f docker-compose.prod.yml up -d --remove-orphans
docker compose -f docker-compose.prod.yml ps
curl --fail --show-error https://statuspulse.org/up
```

Only after the health check passes, remove unused Docker objects older than seven days:

```bash
docker system prune -af --filter "until=168h"
```

This does not remove named volumes, but read Docker's proposed action before confirming any broader prune command. For failures, inspect the previous image IDs with `docker image ls` and container logs before attempting rollback; schema migrations may require an application-specific rollback plan.

## 11. Troubleshooting and verification

### Action Cable/WebSocket upgrade

A normal `curl https://statuspulse.org/cable` is not a WebSocket test. Send a real HTTP/1.1 upgrade handshake:

```bash
curl --http1.1 --include --no-buffer \
  -H 'Connection: Upgrade' \
  -H 'Upgrade: websocket' \
  -H 'Origin: https://statuspulse.org' \
  -H 'Sec-WebSocket-Version: 13' \
  -H 'Sec-WebSocket-Key: SGVybWVzU3RhdHVzUHVsc2U=' \
  https://statuspulse.org/cable
```

A working path returns `HTTP/1.1 101 Switching Protocols` and keeps the connection open; use `Ctrl-C` after confirmation. A `400`/`404` suggests the handshake or cable mount is wrong, `403` usually indicates Action Cable origin policy, and `502` means Apache cannot reach Puma. Check that `proxy_wstunnel_module` is loaded and that the WebSocket rewrite appears before `ProxyPass /`:

```bash
sudo apache2ctl -M | grep proxy_wstunnel
sudo tail -f /var/log/apache2/statuspulse/error.log /var/log/apache2/statuspulse/access.log
docker compose -f /opt/statuspulse/docker-compose.prod.yml logs -f web
```

The dedicated Apache access log includes `upgrade="websocket"`, making it possible to distinguish a real handshake from an ordinary GET.

### Forwarded HTTPS protocol

The SSL vhost sets `X-Forwarded-Proto: https`. Its access-log format records the received/effective value as `xfp="https"`:

```bash
curl -sS -o /dev/null https://statuspulse.org/up
sudo tail -n 5 /var/log/apache2/statuspulse/access.log
```

The matching line must contain `xfp="https"`. Repeated 301 responses at the apex usually mean this header is absent or Rails' reverse-proxy SSL settings do not match the deployment. Compare the edge response and direct loopback response:

```bash
curl -I https://statuspulse.org/up
curl -I -H 'Host: statuspulse.org' -H 'X-Forwarded-Proto: https' http://127.0.0.1:3000/up
```

### Real client IPs

Apache obtains the network peer address directly in this topology and passes its immutable connection address to Rails in `X-Forwarded-For`. The vhost loads/configures `mod_remoteip` with only loopback proxies trusted, disables automatic proxy headers, and overwrites any client-supplied forwarding value. Compare the connection address at the beginning of the Apache access line with Rails' request/container logs:

```bash
sudo tail -n 20 /var/log/apache2/statuspulse/access.log
docker compose -f /opt/statuspulse/docker-compose.prod.yml logs --tail=100 web
```

If a CDN or Lightsail load balancer is introduced later, do not trust all forwarded addresses. Add only that provider's documented proxy networks to `RemoteIPTrustedProxy`, then retest logging.

### Logs and service state

```bash
sudo journalctl -u apache2 --since '30 minutes ago'
sudo tail -n 100 /var/log/apache2/statuspulse/error.log
sudo tail -n 100 /var/log/apache2/statuspulse/access.log
docker compose -f /opt/statuspulse/docker-compose.prod.yml ps
docker compose -f /opt/statuspulse/docker-compose.prod.yml logs --tail=200 web db
sudo apache2ctl configtest
```

### TLS, redirects, HTTP/2, and headers

```bash
curl -I http://statuspulse.org/
curl -I https://www.statuspulse.org/
curl --http2 -I https://statuspulse.org/
openssl s_client -connect statuspulse.org:443 -servername statuspulse.org -status </dev/null
```

Confirm the apex response includes HSTS, `nosniff`, referrer, permissions, and frame protections; the `www` response is a permanent redirect to the apex; HTTP/2 is negotiated; and the certificate chain and OCSP response are valid. Note that OCSP stapling availability ultimately depends on the certificate authority's responder and certificate metadata.

---

## Backups

Nightly `pg_dumpall`, 14 days local and 90 days offsite in S3 with write-only
credentials. Setup, the IAM policy, and the restore procedure are in
[`docs/BACKUPS.md`](docs/BACKUPS.md).

**Do not restore a `pg_dumpall` into the running cluster** — it will apply rows
to the live databases. The restore procedure uses an isolated throwaway cluster.

#!/usr/bin/env bash
#
# Nightly PostgreSQL backup for StatusPulse.
#
# Dumps the whole cluster (all four Rails databases), keeps a short local
# history for fast restores, and ships a copy offsite to S3 so the backups do
# not die with the instance they protect.
#
# The S3 credentials are deliberately write-only: the IAM user can PutObject
# and nothing else. A compromised server therefore cannot read the backup
# history or delete it, which is the first thing ransomware goes looking for.
# See DEPLOY.md for the policy.
#
# Run from cron:
#   17 3 * * * /opt/statuspulse/script/backup.sh >> /var/backups/statuspulse/backup.log 2>&1

set -euo pipefail
umask 077

APP_DIR="${APP_DIR:-/opt/statuspulse}"
DEST="${BACKUP_DIR:-/var/backups/statuspulse}"
LOCAL_RETENTION_DAYS="${LOCAL_RETENTION_DAYS:-14}"
COMPOSE_FILE="$APP_DIR/docker-compose.prod.yml"

# AWS credentials live in their own file rather than the application .env, so
# the backup job never has to read the app's secrets.
CREDS_FILE="${BACKUP_CREDS_FILE:-$APP_DIR/.env.backup}"

log() { printf '%s  %s\n' "$(date -u '+%Y-%m-%d %H:%M:%SZ')" "$*"; }
fail() { log "ERROR: $*"; exit 1; }

STAMP="$(date -u +%Y%m%d-%H%M%S)"
ARCHIVE="$DEST/statuspulse-$STAMP.sql.gz"
PARTIAL="$ARCHIVE.partial"

install -d -m 0700 "$DEST"

# ---- dump -------------------------------------------------------------------

log "dumping cluster"
docker compose -f "$COMPOSE_FILE" exec -T db \
  pg_dumpall -U postgres | gzip > "$PARTIAL"

# A dump that fails midway still leaves a valid gzip of a truncated file, so
# check the content rather than the exit status alone.
gzip -t "$PARTIAL" || fail "archive is not valid gzip: $PARTIAL"
SIZE=$(stat -c %s "$PARTIAL")
[ "$SIZE" -gt 1000 ] || fail "archive is implausibly small (${SIZE} bytes): $PARTIAL"
# pipefail is disabled for this check only. `grep -q` exits at the first match
# and closes the pipe, so gunzip dies of SIGPIPE (141) — and under pipefail that
# reads as failure. The header is on line 2, so the more valid the archive the
# faster it "failed". Reading a bounded head also avoids decompressing the whole
# file just to inspect its first line.
set +o pipefail
gunzip -c "$PARTIAL" 2>/dev/null | head -c 65536 | grep -q "PostgreSQL database cluster dump" \
  || fail "archive does not look like a pg_dumpall: $PARTIAL"
set -o pipefail

chmod 0600 "$PARTIAL"
mv "$PARTIAL" "$ARCHIVE"

log "dumped $(numfmt --to=iec "$SIZE" 2>/dev/null || echo "${SIZE}B") to $ARCHIVE"

# ---- ship offsite -----------------------------------------------------------

if [ -f "$CREDS_FILE" ]; then
  # shellcheck disable=SC1090
  set -a; . "$CREDS_FILE"; set +a

  if [ -n "${BACKUP_S3_BUCKET:-}" ]; then
    command -v aws >/dev/null 2>&1 || fail "aws CLI not installed but BACKUP_S3_BUCKET is set"

    KEY="s3://$BACKUP_S3_BUCKET/${BACKUP_S3_PREFIX:-statuspulse}/$(basename "$ARCHIVE")"
    log "uploading to $KEY"

    # The bucket enforces SSE-S3; asking for it explicitly means a
    # misconfigured bucket fails the upload rather than silently storing
    # plaintext.
    aws s3 cp "$ARCHIVE" "$KEY" --sse AES256 --only-show-errors \
      || fail "upload failed — local copy retained at $ARCHIVE"

    log "uploaded"
  else
    log "BACKUP_S3_BUCKET unset; keeping local copy only"
  fi
else
  log "no $CREDS_FILE; keeping local copy only"
fi

# ---- prune local ------------------------------------------------------------
#
# Only local copies are pruned here. S3 retention is a bucket lifecycle rule, so
# the server has no ability to expire anything offsite.

DELETED=$(find "$DEST" -name 'statuspulse-*.sql.gz' -mtime +"$LOCAL_RETENTION_DAYS" -print -delete | wc -l)
log "pruned $DELETED local archive(s) older than ${LOCAL_RETENTION_DAYS}d"
log "done"

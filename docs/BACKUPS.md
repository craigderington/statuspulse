# Backups

Nightly `pg_dumpall` of the whole cluster, kept locally for 14 days and shipped
to S3 for 90.

Script: [`script/backup.sh`](../script/backup.sh)

---

## Design

**Write-only offsite credentials.** The IAM user on the instance can `PutObject`
and nothing else — it cannot list, read, or delete. A compromised server can
therefore neither exfiltrate the backup history nor destroy it, which is the
first thing ransomware attempts. Expiry is handled by a bucket lifecycle rule,
so nothing on the server has the ability to remove an offsite copy.

**Bucket versioning is on.** Even overwriting today's object leaves the previous
version recoverable.

**Whole-cluster dumps.** Rails 8 uses four databases (`statuspulse_production`
plus `_cache`, `_queue`, `_cable`). A dump of the primary alone will not boot the
application.

**The dump is verified, not assumed.** A `pg_dumpall` that dies midway still
produces a valid gzip of a truncated file, so the script checks the archive
decompresses, is a plausible size, and contains the pg_dumpall header before
treating it as a backup.

---

## One-time setup

### 1. Create the bucket

Replace `BUCKET` with a globally unique name and `REGION` with your Lightsail
region.

```bash
aws s3api create-bucket --bucket BUCKET --region REGION \
  --create-bucket-configuration LocationConstraint=REGION

aws s3api put-public-access-block --bucket BUCKET \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api put-bucket-versioning --bucket BUCKET \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption --bucket BUCKET \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
```

Public access blocking matters more than usual: these dumps contain every user's
email address and bcrypt password hash.

### 2. Lifecycle: 30 days standard, then Glacier, expire at 90

```bash
aws s3api put-bucket-lifecycle-configuration --bucket BUCKET \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "statuspulse-backup-retention",
      "Status": "Enabled",
      "Filter": {"Prefix": "statuspulse/"},
      "Transitions": [{"Days": 30, "StorageClass": "GLACIER_IR"}],
      "Expiration": {"Days": 90},
      "NoncurrentVersionExpiration": {"NoncurrentDays": 90}
    }]
  }'
```

### 3. Write-only IAM user

```bash
aws iam create-user --user-name statuspulse-backup

aws iam put-user-policy --user-name statuspulse-backup \
  --policy-name statuspulse-backup-write-only \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Sid": "WriteOnlyBackups",
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::BUCKET/statuspulse/*"
    }]
  }'

aws iam create-access-key --user-name statuspulse-backup
```

`s3:PutObject` only. No `GetObject`, no `DeleteObject`, no `ListBucket`. Restores
are performed with your own credentials, from your own machine — not from the
server.

### 4. Credentials on the instance

```bash
sudo apt install -y awscli    # or the AWS CLI v2 installer

cat > /opt/statuspulse/.env.backup <<'EOF'
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_DEFAULT_REGION=...
BACKUP_S3_BUCKET=...
BACKUP_S3_PREFIX=statuspulse
EOF

chmod 600 /opt/statuspulse/.env.backup
```

Separate from the application `.env` so the backup job never reads the app's
secrets, and the app never sees the AWS keys.

### 5. Install and verify

```bash
chmod +x /opt/statuspulse/script/backup.sh
/opt/statuspulse/script/backup.sh

( crontab -l 2>/dev/null | grep -v statuspulse/script/backup.sh;
  echo "17 3 * * * /opt/statuspulse/script/backup.sh >> /var/backups/statuspulse/backup.log 2>&1" ) | crontab -
```

You will not be able to confirm the upload from the server — the credentials
cannot list the bucket, by design. Check from your own machine:

```bash
aws s3 ls s3://BUCKET/statuspulse/
```

---

## Restoring

**Never restore a `pg_dumpall` into the running cluster.** It contains
`CREATE DATABASE` and `\connect` for each database; against a live cluster the
creates fail, `\connect` switches to the *real* database, and the dump's rows are
applied to production.

Restore into an isolated throwaway cluster instead. This also proves the dump can
rebuild from nothing:

```bash
docker run --rm -d --name pg-restore-test \
  -e POSTGRES_PASSWORD=scratch \
  -v /var/backups/statuspulse:/backups:ro \
  postgres:16-alpine

until docker exec pg-restore-test pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done

docker exec -i pg-restore-test sh -c \
  "gunzip -c /backups/statuspulse-YYYYMMDD-HHMMSS.sql.gz | psql -U postgres -q postgres"
```

Then verify it actually contains data — a restore into an empty cluster also
"runs clean":

```bash
docker exec pg-restore-test psql -U postgres -d statuspulse_production -c "
  SELECT (SELECT count(*) FROM organizations) AS orgs,
         (SELECT count(*) FROM users) AS users,
         (SELECT count(*) FROM services) AS services,
         (SELECT count(*) FROM check_logs) AS check_logs;"

docker exec pg-restore-test psql -U postgres -lqt | cut -d'|' -f1 | grep statuspulse

docker rm -f pg-restore-test
```

Expect four databases and row counts matching production.

Last verified: 2026-08-12 — counts matched, all four databases present.

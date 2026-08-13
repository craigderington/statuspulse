# Bounds the only table in the app that grows without limit.
#
# check_logs accrues one row per service per check interval, forever. Left
# alone that is millions of rows a year, and every dashboard load scans 30 days
# of it to compute uptime.
class PurgeCheckLogsJob < ApplicationJob
  queue_as :default

  # Deleted in batches rather than one statement: a single DELETE over months of
  # accumulated rows takes a long lock on a table the app reads on every
  # dashboard load.
  BATCH_SIZE = 5_000

  def perform
    cutoff = CheckLog.retention_cutoff
    deleted = 0

    loop do
      batch = CheckLog.expired.limit(BATCH_SIZE).pluck(:id)
      break if batch.empty?

      deleted += CheckLog.where(id: batch).delete_all
    end

    Rails.logger.info(
      "PurgeCheckLogsJob deleted #{deleted} check logs older than #{cutoff.iso8601} " \
      "(retention #{CheckLog.retention_days} days)"
    )

    deleted
  end
end

class AddServiceCreatedAtIndexToCheckLogs < ActiveRecord::Migration[8.1]
  def change
    # Every read of this table is "one service's checks, newest first" — the
    # paginated list, history_bars, uptime_percentage and average_response_time.
    # The existing service_id-only index makes Postgres fetch every row for the
    # service and sort it; at 1,440 rows per service per day that stops being
    # free quickly.
    add_index :check_logs, [ :service_id, :created_at ]

    # Superseded: the composite index serves service_id lookups on its own.
    remove_index :check_logs, :service_id
  end
end

class AddPausedAtToServices < ActiveRecord::Migration[8.1]
  def change
    # Nullable timestamp rather than a boolean: knowing *when* monitoring was
    # suspended is useful when reconciling an SLA gap after the fact.
    add_column :services, :paused_at, :datetime, null: true

    # The recurring sweep filters on this every minute.
    add_index :services, :paused_at
  end
end

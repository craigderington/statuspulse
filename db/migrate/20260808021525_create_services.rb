class CreateServices < ActiveRecord::Migration[8.1]
  def change
    create_table :services do |t|
      t.string :name, null: false
      t.text :description
      t.string :url, null: false
      t.string :http_method, default: "GET", null: false
      t.text :headers
      t.text :request_body
      t.string :expected_body_match
      t.integer :expected_status_code, default: 200, null: false
      t.integer :timeout_seconds, default: 10, null: false
      t.integer :check_interval_seconds, default: 60, null: false
      t.string :status, default: "operational", null: false
      t.datetime :last_checked_at
      t.integer :last_response_time_ms
      t.integer :last_status_code
      t.integer :position, default: 0

      t.timestamps
    end
  end
end

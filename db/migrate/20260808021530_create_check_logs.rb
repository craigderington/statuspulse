class CreateCheckLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :check_logs do |t|
      t.references :service, null: false, foreign_key: true
      t.integer :status_code
      t.integer :response_time_ms
      t.boolean :success
      t.string :error_message

      t.timestamps
    end
  end
end

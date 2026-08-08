class CreateIncidentServices < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_services do |t|
      t.references :incident, null: false, foreign_key: true
      t.references :service, null: false, foreign_key: true

      t.timestamps
    end
  end
end

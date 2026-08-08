class CreateIncidentUpdates < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_updates do |t|
      t.references :incident, null: false, foreign_key: true
      t.string :status
      t.text :body

      t.timestamps
    end
  end
end

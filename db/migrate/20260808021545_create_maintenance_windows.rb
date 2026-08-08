class CreateMaintenanceWindows < ActiveRecord::Migration[8.1]
  def change
    create_table :maintenance_windows do |t|
      t.string :title
      t.text :description
      t.datetime :starts_at
      t.datetime :ends_at
      t.string :status

      t.timestamps
    end
  end
end

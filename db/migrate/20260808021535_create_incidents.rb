class CreateIncidents < ActiveRecord::Migration[8.1]
  def change
    create_table :incidents do |t|
      t.string :title
      t.text :description
      t.string :status
      t.string :severity
      t.datetime :resolved_at

      t.timestamps
    end
  end
end

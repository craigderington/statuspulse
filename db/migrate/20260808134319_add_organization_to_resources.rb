class AddOrganizationToResources < ActiveRecord::Migration[8.1]
  def change
    add_reference :services, :organization, foreign_key: true
    add_reference :incidents, :organization, foreign_key: true
    add_reference :maintenance_windows, :organization, foreign_key: true
  end
end

class CreateOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations do |t|
      t.string :name
      t.string :slug
      t.boolean :weekly_digest_enabled

      t.timestamps
    end
  end
end

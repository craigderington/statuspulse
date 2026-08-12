class AddStatusPageIndexableToOrganizations < ActiveRecord::Migration[8.1]
  def change
    # Defaults to true: a status page exists so a client's customers can find it
    # when they suspect an outage, and hiding it from search undercuts the whole
    # feature. Tenants who want theirs unlisted can opt out.
    add_column :organizations, :status_page_indexable, :boolean, default: true, null: false
  end
end

class EnforceIncidentTenantBoundaries < ActiveRecord::Migration[8.1]
  class MigrationIncident < ActiveRecord::Base
    self.table_name = "incidents"
  end

  class MigrationIncidentService < ActiveRecord::Base
    self.table_name = "incident_services"
  end

  def up
    # Legacy incidents predate workspaces. A linked service is authoritative;
    # ambiguous or unlinked data must be repaired explicitly instead of being
    # silently assigned to an arbitrary tenant.
    MigrationIncident.where(organization_id: nil).find_each do |incident|
      organization_ids = select_values(<<~SQL).compact.map(&:to_i).uniq
        SELECT services.organization_id
        FROM services
        INNER JOIN incident_services ON incident_services.service_id = services.id
        WHERE incident_services.incident_id = #{quote(incident.id)}
      SQL

      unless organization_ids.one?
        raise ActiveRecord::MigrationError,
              "incident #{incident.id} has no unambiguous workspace; assign it before migrating"
      end

      incident.update_columns(organization_id: organization_ids.first)
    end

    mismatches = select_value(<<~SQL).to_i
      SELECT COUNT(*)
      FROM incident_services
      INNER JOIN incidents ON incidents.id = incident_services.incident_id
      INNER JOIN services ON services.id = incident_services.service_id
      WHERE incidents.organization_id <> services.organization_id
    SQL
    raise ActiveRecord::MigrationError, "cross-workspace incident services exist" if mismatches.positive?

    change_column_null :services, :organization_id, false
    change_column_null :incidents, :organization_id, false

    add_reference :incident_services, :organization, foreign_key: true
    execute <<~SQL
      UPDATE incident_services
      SET organization_id = (
        SELECT organization_id FROM incidents
        WHERE incidents.id = incident_services.incident_id
      )
    SQL
    change_column_null :incident_services, :organization_id, false

    add_index :incidents, [ :id, :organization_id ], unique: true
    add_index :services, [ :id, :organization_id ], unique: true
    add_index :incident_services, [ :incident_id, :organization_id ],
              name: "idx_incident_services_incident_org"
    add_index :incident_services, [ :service_id, :organization_id ],
              name: "idx_incident_services_service_org"

    add_foreign_key :incident_services, :incidents,
                    column: [ :incident_id, :organization_id ],
                    primary_key: [ :id, :organization_id ],
                    name: "fk_incident_services_incident_org"
    add_foreign_key :incident_services, :services,
                    column: [ :service_id, :organization_id ],
                    primary_key: [ :id, :organization_id ],
                    name: "fk_incident_services_service_org"
  end

  def down
    remove_foreign_key :incident_services, name: "fk_incident_services_service_org"
    remove_foreign_key :incident_services, name: "fk_incident_services_incident_org"
    remove_index :incident_services, name: "idx_incident_services_service_org"
    remove_index :incident_services, name: "idx_incident_services_incident_org"
    remove_index :services, column: [ :id, :organization_id ]
    remove_index :incidents, column: [ :id, :organization_id ]
    remove_reference :incident_services, :organization, foreign_key: true
    change_column_null :incidents, :organization_id, true
    change_column_null :services, :organization_id, true
  end
end

# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_08_134319) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "check_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "error_message"
    t.integer "response_time_ms"
    t.integer "service_id", null: false
    t.integer "status_code"
    t.boolean "success"
    t.datetime "updated_at", null: false
    t.index ["service_id"], name: "index_check_logs_on_service_id"
  end

  create_table "incident_services", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "incident_id", null: false
    t.integer "service_id", null: false
    t.datetime "updated_at", null: false
    t.index ["incident_id"], name: "index_incident_services_on_incident_id"
    t.index ["service_id"], name: "index_incident_services_on_service_id"
  end

  create_table "incident_updates", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.integer "incident_id", null: false
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["incident_id"], name: "index_incident_updates_on_incident_id"
  end

  create_table "incidents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "organization_id"
    t.datetime "resolved_at"
    t.string "severity"
    t.string "status"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_incidents_on_organization_id"
  end

  create_table "maintenance_windows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "ends_at"
    t.bigint "organization_id"
    t.datetime "starts_at"
    t.string "status"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_maintenance_windows_on_organization_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.string "slug"
    t.datetime "updated_at", null: false
    t.boolean "weekly_digest_enabled"
  end

  create_table "services", force: :cascade do |t|
    t.integer "check_interval_seconds", default: 60, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "expected_body_match"
    t.integer "expected_status_code", default: 200, null: false
    t.text "headers"
    t.string "http_method", default: "GET", null: false
    t.datetime "last_checked_at"
    t.integer "last_response_time_ms"
    t.integer "last_status_code"
    t.string "name", null: false
    t.bigint "organization_id"
    t.integer "position", default: 0
    t.text "request_body"
    t.string "status", default: "operational", null: false
    t.integer "timeout_seconds", default: 10, null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["organization_id"], name: "index_services_on_organization_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name"
    t.bigint "organization_id", null: false
    t.string "password_digest"
    t.string "role"
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_users_on_organization_id"
  end

  add_foreign_key "check_logs", "services"
  add_foreign_key "incident_services", "incidents"
  add_foreign_key "incident_services", "services"
  add_foreign_key "incident_updates", "incidents"
  add_foreign_key "incidents", "organizations"
  add_foreign_key "maintenance_windows", "organizations"
  add_foreign_key "services", "organizations"
  add_foreign_key "users", "organizations"
end

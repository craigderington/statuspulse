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

ActiveRecord::Schema[8.1].define(version: 2026_08_18_162000) do
  create_table "check_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "error_message"
    t.integer "response_time_ms"
    t.integer "service_id", null: false
    t.integer "status_code"
    t.boolean "success"
    t.datetime "updated_at", null: false
    t.index ["service_id", "created_at"], name: "index_check_logs_on_service_id_and_created_at"
  end

  create_table "incident_services", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "incident_id", null: false
    t.integer "organization_id", null: false
    t.integer "service_id", null: false
    t.datetime "updated_at", null: false
    t.index ["incident_id", "organization_id"], name: "idx_incident_services_incident_org"
    t.index ["incident_id"], name: "index_incident_services_on_incident_id"
    t.index ["organization_id"], name: "index_incident_services_on_organization_id"
    t.index ["service_id", "organization_id"], name: "idx_incident_services_service_org"
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
    t.integer "organization_id", null: false
    t.datetime "resolved_at"
    t.string "severity"
    t.string "status"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["id", "organization_id"], name: "index_incidents_on_id_and_organization_id", unique: true
    t.index ["organization_id"], name: "index_incidents_on_organization_id"
  end

  create_table "maintenance_windows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "ends_at"
    t.integer "organization_id"
    t.datetime "starts_at"
    t.string "status"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_maintenance_windows_on_organization_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.string "alert_webhook_secret"
    t.string "alert_webhook_url"
    t.boolean "alerts_enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name"
    t.string "slug"
    t.boolean "status_page_indexable", default: true, null: false
    t.datetime "updated_at", null: false
    t.boolean "weekly_digest_enabled"
  end

  create_table "recovery_codes", force: :cascade do |t|
    t.string "code_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.integer "user_id", null: false
    t.index ["user_id", "used_at"], name: "index_recovery_codes_on_user_id_and_used_at"
    t.index ["user_id"], name: "index_recovery_codes_on_user_id"
  end

  create_table "services", force: :cascade do |t|
    t.datetime "alerted_at"
    t.integer "check_interval_seconds", default: 60, null: false
    t.integer "consecutive_failures", default: 0, null: false
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
    t.integer "organization_id", null: false
    t.datetime "paused_at"
    t.integer "position", default: 0
    t.text "request_body"
    t.string "status", default: "operational", null: false
    t.integer "timeout_seconds", default: 10, null: false
    t.datetime "tls_alerted_at"
    t.datetime "tls_expires_at"
    t.string "tls_issuer"
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.boolean "verify_tls", default: true, null: false
    t.index ["id", "organization_id"], name: "index_services_on_id_and_organization_id", unique: true
    t.index ["organization_id"], name: "index_services_on_organization_id"
    t.index ["paused_at"], name: "index_services_on_paused_at"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name"
    t.integer "organization_id", null: false
    t.string "password_digest"
    t.string "role", default: "member", null: false
    t.datetime "totp_enabled_at"
    t.bigint "totp_last_timestep"
    t.text "totp_secret"
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_users_on_organization_id"
  end

  add_foreign_key "check_logs", "services"
  add_foreign_key "incident_services", "incidents"
  add_foreign_key "incident_services", "incidents", column: ["incident_id", "organization_id"], primary_key: ["id", "organization_id"]
  add_foreign_key "incident_services", "organizations"
  add_foreign_key "incident_services", "services"
  add_foreign_key "incident_services", "services", column: ["service_id", "organization_id"], primary_key: ["id", "organization_id"]
  add_foreign_key "incident_updates", "incidents"
  add_foreign_key "incidents", "organizations"
  add_foreign_key "maintenance_windows", "organizations"
  add_foreign_key "recovery_codes", "users"
  add_foreign_key "services", "organizations"
  add_foreign_key "users", "organizations"
end

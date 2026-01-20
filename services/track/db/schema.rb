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

ActiveRecord::Schema[8.1].define(version: 2026_01_19_160843) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "deliveries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.string "email"
    t.string "frequency"
    t.string "phone"
    t.string "secret"
    t.bigint "track_id", null: false
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["track_id"], name: "index_deliveries_on_track_id"
    t.check_constraint "type::text = 'EmailDelivery'::text AND email IS NOT NULL AND frequency IS NOT NULL OR type::text <> 'EmailDelivery'::text", name: "check_email_delivery"
    t.check_constraint "type::text = 'SmsDelivery'::text AND phone IS NOT NULL OR type::text <> 'SmsDelivery'::text", name: "check_sms_delivery"
    t.check_constraint "type::text = 'WebhookDelivery'::text AND url IS NOT NULL OR type::text <> 'WebhookDelivery'::text", name: "check_webhook_delivery"
  end

  create_table "matches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "data"
    t.bigint "track_id", null: false
    t.datetime "updated_at", null: false
    t.index ["track_id"], name: "index_matches_on_track_id"
  end

  create_table "tracks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "external_id", null: false
    t.text "keywords", default: [], array: true
    t.string "name", null: false
    t.text "query", null: false
    t.string "status", default: "pending", null: false
    t.float "threshold", default: 0.0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["external_id"], name: "index_tracks_on_external_id", unique: true
    t.index ["user_id"], name: "index_tracks_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.text "access_token"
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.string "did"
    t.string "display_name"
    t.datetime "expires_at"
    t.string "feed_token"
    t.string "handle"
    t.text "refresh_token"
    t.datetime "updated_at", null: false
    t.index ["did"], name: "index_users_on_did"
    t.index ["feed_token"], name: "index_users_on_feed_token", unique: true
  end

  add_foreign_key "deliveries", "tracks"
  add_foreign_key "matches", "tracks"
  add_foreign_key "tracks", "users"
end

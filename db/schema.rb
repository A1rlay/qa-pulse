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

ActiveRecord::Schema[8.1].define(version: 2026_11_23_000929) do
  create_table "projects", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "name", limit: 100, null: false
    t.string "slug", limit: 100, null: false
    t.string "api_token", limit: 64, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_token"], name: "index_projects_on_api_token", unique: true
    t.index ["slug"], name: "index_projects_on_slug", unique: true
  end

  create_table "runs", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.string "branch"
    t.string "commit_sha", limit: 64
    t.datetime "started_at", null: false
    t.integer "duration_ms", default: 0, null: false
    t.integer "total", default: 0, null: false
    t.integer "passed", default: 0, null: false
    t.integer "failed", default: 0, null: false
    t.integer "skipped", default: 0, null: false
    t.integer "flaky", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "started_at"], name: "index_runs_on_project_id_and_started_at"
    t.check_constraint "(`duration_ms` >= 0) and (`passed` >= 0) and (`failed` >= 0) and (`skipped` >= 0) and (`flaky` >= 0)", name: "runs_non_negative"
    t.check_constraint "`total` = (((`passed` + `failed`) + `skipped`) + `flaky`)", name: "runs_total_matches"
  end

  create_table "test_results", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "run_id", null: false
    t.string "file", limit: 500, null: false
    t.text "title", null: false
    t.string "project_name", limit: 100, default: "", null: false
    t.string "test_key", limit: 64, null: false
    t.string "status", limit: 10, null: false
    t.integer "duration_ms", default: 0, null: false
    t.integer "retries", default: 0, null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["run_id", "status"], name: "index_test_results_on_run_id_and_status"
    t.index ["test_key", "run_id"], name: "index_test_results_on_test_key_and_run_id"
    t.check_constraint "(`duration_ms` >= 0) and (`retries` >= 0)", name: "test_results_non_negative"
    t.check_constraint "`status` in (_utf8mb4'passed',_utf8mb4'failed',_utf8mb4'skipped',_utf8mb4'flaky')", name: "test_results_status_valid"
  end

  add_foreign_key "runs", "projects"
  add_foreign_key "test_results", "runs"
end

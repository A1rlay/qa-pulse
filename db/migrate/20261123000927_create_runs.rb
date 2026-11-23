class CreateRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :runs do |t|
      t.references :project, null: false, foreign_key: true, index: false
      t.string :branch, limit: 255
      t.string :commit_sha, limit: 64
      t.datetime :started_at, null: false
      t.integer :duration_ms, null: false, default: 0
      t.integer :total, null: false, default: 0
      t.integer :passed, null: false, default: 0
      t.integer :failed, null: false, default: 0
      t.integer :skipped, null: false, default: 0
      t.integer :flaky, null: false, default: 0
      t.timestamps
    end
    # Covers "last N runs of a project" (dashboard, charts, flaky rule) and the FK.
    add_index :runs, [ :project_id, :started_at ]
    add_check_constraint :runs,
      "duration_ms >= 0 AND passed >= 0 AND failed >= 0 AND skipped >= 0 AND flaky >= 0",
      name: "runs_non_negative"
    add_check_constraint :runs, "total = passed + failed + skipped + flaky", name: "runs_total_matches"
  end
end

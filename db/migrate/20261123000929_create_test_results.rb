class CreateTestResults < ActiveRecord::Migration[8.1]
  def change
    create_table :test_results do |t|
      t.references :run, null: false, foreign_key: true, index: false
      t.string :file, null: false, limit: 500
      t.text :title, null: false
      t.string :project_name, null: false, limit: 100, default: ""
      # SHA-256 of file + title + project_name: a fixed-width, case-sensitive identity
      # that MySQL can index fully (title is TEXT and the default collation ignores case).
      t.string :test_key, null: false, limit: 64
      t.string :status, null: false, limit: 10
      t.integer :duration_ms, null: false, default: 0
      t.integer :retries, null: false, default: 0
      t.text :error_message
      t.timestamps
    end
    add_index :test_results, [ :run_id, :status ]
    add_index :test_results, [ :test_key, :run_id ]
    add_check_constraint :test_results, "status IN ('passed','failed','skipped','flaky')",
      name: "test_results_status_valid"
    add_check_constraint :test_results, "duration_ms >= 0 AND retries >= 0",
      name: "test_results_non_negative"
  end
end

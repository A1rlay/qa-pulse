class Run < ApplicationRecord
  belongs_to :project
  has_many :test_results, dependent: :delete_all

  validates :started_at, presence: true
  validates :total, :passed, :failed, :skipped, :flaky, :duration_ms,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Never trust client counts: derive every counter from the stored results.
  def recompute_counts!
    counts = test_results.group(:status).count
    update!(
      passed: counts.fetch("passed", 0), failed: counts.fetch("failed", 0),
      skipped: counts.fetch("skipped", 0), flaky: counts.fetch("flaky", 0),
      total: counts.values.sum
    )
  end

  # Ejecución anterior del mismo proyecto (por fecha, desempatando por id).
  def previous
    project.runs.where("started_at < :t OR (started_at = :t AND id < :id)", t: started_at, id: id)
           .order(started_at: :desc, id: :desc).first
  end

  # Percentage of executed tests (not skipped) that ended green; flaky ends green.
  def pass_rate
    executed = total - skipped
    return 0.0 if executed.zero?
    ((passed + flaky) * 100.0 / executed).round(1)
  end

  def summary
    {
      id: id, branch: branch, commit_sha: commit_sha, started_at: started_at.iso8601,
      duration_ms: duration_ms, total: total, passed: passed, failed: failed,
      skipped: skipped, flaky: flaky, pass_rate: pass_rate
    }
  end
end

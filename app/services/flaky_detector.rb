# Regla de inestabilidad (se explica en la UI):
# en las últimas N ejecuciones del proyecto (por defecto 10), una prueba es inestable si
#   a) Playwright la marcó como "flaky" en al menos una ejecución (falló y pasó al reintentar), o
#   b) su estado cambió entre "passed" y "failed" al menos 2 veces.
# Los estados "skipped" se ignoran al contar cambios; "flaky" no cuenta como cambio.
class FlakyDetector
  DEFAULT_WINDOW = 10
  MIN_FLIPS = 2

  Entry = Struct.new(:test_key, :file, :title, :project_name, :flaky_runs, :flips,
                     :runs_seen, :last_failure_message, :last_failure_at, keyword_init: true) do
    def score = flaky_runs + flips

    def as_json(*)
      to_h.merge(score: score, last_failure_at: last_failure_at&.iso8601)
    end
  end

  def initialize(project, window: DEFAULT_WINDOW, branch: nil)
    @project = project
    @window = window.to_i.clamp(1, 100)
    @branch = branch.presence
  end

  def call
    run_ids = @project.recent_runs(@window, branch: @branch).pluck(:id)
    return [] if run_ids.empty?

    rows = TestResult.joins(:run).where(run_id: run_ids)
                     .order("runs.started_at ASC, runs.id ASC")
                     .pluck(:test_key, :file, :title, :project_name, :status,
                            :error_message, "runs.started_at")

    rows.group_by(&:first).filter_map { |key, history| evaluate(key, history) }
        .sort_by { |e| [ -e.score, -e.flips, e.title ] }
  end

  private

  def evaluate(key, history)
    statuses = history.map { |row| row[4] }
    flaky_runs = statuses.count("flaky")
    flips = count_flips(statuses)
    return unless flaky_runs.positive? || flips >= MIN_FLIPS

    last_failure = history.reverse.find { |row| %w[failed flaky].include?(row[4]) && row[5].present? }
    _, file, title, project_name = history.last
    Entry.new(test_key: key, file: file, title: title, project_name: project_name,
              flaky_runs: flaky_runs, flips: flips, runs_seen: statuses.size,
              last_failure_message: last_failure&.at(5), last_failure_at: last_failure&.at(6))
  end

  def count_flips(statuses)
    decisive = statuses.select { |s| %w[passed failed].include?(s) }
    decisive.each_cons(2).count { |a, b| a != b }
  end
end

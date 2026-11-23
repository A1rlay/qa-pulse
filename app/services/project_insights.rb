# Métricas agregadas de las últimas N ejecuciones de un proyecto (página "Insights").
class ProjectInsights
  DEFAULT_WINDOW = 20
  SLOWEST_LIMIT = 10
  HEATMAP_LIMIT = 25

  def initialize(project, window: DEFAULT_WINDOW, branch: nil)
    @project = project
    @window = window.to_i.clamp(1, 100)
    @branch = branch.presence
  end

  def runs
    @runs ||= begin
      scope = @project.recent_runs(@window)
      scope = scope.where(branch: @branch) if @branch
      scope.to_a.reverse
    end
  end

  # Pruebas con mayor duración promedio (sin contar omitidas).
  def slowest
    return [] if runs.empty?
    TestResult.where(run_id: runs.map(&:id)).where.not(status: "skipped")
              .group(:test_key)
              .order(Arel.sql("AVG(duration_ms) DESC"))
              .limit(SLOWEST_LIMIT)
              .pluck(:test_key, Arel.sql("MAX(file)"), Arel.sql("MAX(title)"), Arel.sql("MAX(project_name)"),
                     Arel.sql("AVG(duration_ms)"), Arel.sql("MAX(duration_ms)"), Arel.sql("COUNT(*)"))
              .map do |key, file, title, browser, avg, max, count|
                { test_key: key, file: file, title: title, project_name: browser,
                  avg_ms: avg.to_f.round, max_ms: max, runs: count }
              end
  end

  # Matriz prueba × ejecución, solo con pruebas que fallaron o fueron flaky alguna vez.
  def heatmap
    return { runs: [], tests: [] } if runs.empty?
    run_ids = runs.map(&:id)
    troubled = TestResult.where(run_id: run_ids, status: %w[failed flaky]).group(:test_key)
                         .order(Arel.sql("COUNT(*) DESC")).limit(HEATMAP_LIMIT).count
    return { runs: runs.map(&:summary), tests: [] } if troubled.empty?

    cells = TestResult.where(run_id: run_ids, test_key: troubled.keys)
                      .pluck(:test_key, :run_id, :status, :file, :title, :project_name)
    by_key = cells.group_by(&:first)
    tests = troubled.keys.map do |key|
      rows = by_key.fetch(key, [])
      statuses = rows.to_h { |r| [ r[1], r[2] ] }
      _, _, _, file, title, browser = rows.first
      { test_key: key, file: file, title: title, project_name: browser, problems: troubled[key],
        statuses: run_ids.map { |id| statuses[id] } } # nil = la prueba no existía en esa ejecución
    end
    { runs: runs.map(&:summary), tests: tests }
  end

  def as_json(*)
    { window: @window, branch: @branch, runs: runs.size, slowest: slowest, heatmap: heatmap }
  end
end

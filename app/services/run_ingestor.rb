# Guarda un reporte ya parseado como una ejecución (Run) con sus resultados, todo o nada.
class RunIngestor
  BATCH = 1_000

  def initialize(project, report, branch: nil, commit_sha: nil)
    @project = project
    @report = report
    @branch = branch.presence
    @commit_sha = commit_sha.presence
  end

  def call
    ActiveRecord::Base.transaction do
      run = @project.runs.create!(branch: @branch, commit_sha: @commit_sha,
                                  started_at: @report.started_at, duration_ms: @report.duration_ms)
      now = Time.current
      @report.results.each_slice(BATCH) do |slice|
        TestResult.insert_all!(slice.map { |r| row(run, r, now) })
      end
      run.recompute_counts! # los totales salen de la BD, nunca de `stats` del cliente
      run
    end
  end

  private

  def row(run, r, now)
    {
      run_id: run.id, file: r.file, title: r.title, project_name: r.project_name,
      test_key: TestResult.key_for(r.file, r.title, r.project_name), status: r.status,
      duration_ms: r.duration_ms, retries: r.retries, error_message: r.error_message,
      created_at: now, updated_at: now
    }
  end
end

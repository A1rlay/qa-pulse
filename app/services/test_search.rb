# Búsqueda de pruebas de un proyecto por título o archivo (para el buscador con AJAX).
class TestSearch
  LIMIT = 20
  MIN_LENGTH = 2
  MAX_LENGTH = 100

  def initialize(project, query)
    @project = project
    @query = query.to_s.strip.first(MAX_LENGTH)
  end

  def call
    return [] if @query.length < MIN_LENGTH

    # sanitize_sql_like escapa % y _ para que se busquen literalmente; el valor va como parámetro.
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
    groups = TestResult.joins(:run).where(runs: { project_id: @project.id })
                       .where("test_results.title LIKE :p OR test_results.file LIKE :p", p: pattern)
                       .group(:test_key)
                       .order(Arel.sql("MAX(test_results.run_id) DESC"), Arel.sql("MAX(test_results.title)"))
                       .limit(LIMIT)
                       .pluck(:test_key, Arel.sql("MAX(test_results.file)"), Arel.sql("MAX(test_results.title)"),
                              Arel.sql("MAX(test_results.project_name)"), Arel.sql("MAX(test_results.run_id)"),
                              Arel.sql("COUNT(*)"))
    latest = TestResult.where(run_id: groups.map { |g| g[4] }.uniq, test_key: groups.map(&:first))
                       .pluck(:test_key, :run_id, :status).to_h { |k, r, s| [ [ k, r ], s ] }

    groups.map do |key, file, title, browser, last_run_id, count|
      { test_key: key, file: file, title: title, project_name: browser,
        last_status: latest[[ key, last_run_id ]], last_run_id: last_run_id, runs: count }
    end
  end
end

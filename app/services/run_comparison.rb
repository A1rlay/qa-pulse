# Compara dos ejecuciones de un proyecto prueba por prueba (identidad = test_key).
#   base = la ejecución "de antes", head = la "de después".
class RunComparison
  SLOWER_RATIO = 1.5   # al menos 50 % más lenta...
  SLOWER_MIN_MS = 200  # ...y al menos 200 ms más (evita ruido en pruebas muy rápidas)
  SLOWER_LIMIT = 10

  Row = Struct.new(:test_key, :file, :title, :project_name, :before, :after,
                   :before_ms, :after_ms, :error_message, keyword_init: true) do
    def delta_ms = after_ms.to_i - before_ms.to_i
  end

  CATEGORIES = %i[new_failures fixed new_flaky still_failing added removed].freeze

  attr_reader :base, :head, :slower, *CATEGORIES

  def initialize(base, head)
    raise ArgumentError, "las ejecuciones deben ser del mismo proyecto" unless base.project_id == head.project_id
    @base = base
    @head = head
    CATEGORIES.each { |c| instance_variable_set("@#{c}", []) }
    compute
  end

  def summary
    {
      base: base.summary, head: head.summary,
      pass_rate_delta: (head.pass_rate - base.pass_rate).round(1),
      duration_delta_ms: head.duration_ms - base.duration_ms,
      counts: CATEGORIES.to_h { |c| [ c, public_send(c).size ] }.merge(slower: slower.size)
    }
  end

  def changes? = CATEGORIES.excluding(:still_failing).any? { |c| public_send(c).any? } || slower.any?

  private

  def results_for(run)
    run.test_results.pluck(:test_key, :file, :title, :project_name, :status, :duration_ms, :error_message)
       .each_with_object({}) { |row, h| h[row[0]] ||= row } # con --repeat-each se toma la primera
  end

  def compute
    before = results_for(base)
    after = results_for(head)
    slower = []

    (before.keys | after.keys).each do |key|
      b = before[key]
      a = after[key]
      ref = a || b
      row = Row.new(test_key: key, file: ref[1], title: ref[2], project_name: ref[3],
                    before: b&.at(4), after: a&.at(4), before_ms: b&.at(5), after_ms: a&.at(5),
                    error_message: a&.at(6))
      category(row)&.then { |c| instance_variable_get("@#{c}") << row }
      slower << row if slower?(row)
    end

    @slower = slower.sort_by { |r| -r.delta_ms }.first(SLOWER_LIMIT)
    CATEGORIES.each { |c| instance_variable_get("@#{c}").sort_by! { |r| [ r.file, r.title ] } }
  end

  def category(row)
    return :removed if row.after.nil?
    return (row.after == "failed" ? :new_failures : :added) if row.before.nil?

    if row.after == "failed"
      row.before == "failed" ? :still_failing : :new_failures
    elsif row.before == "failed" && %w[passed flaky].include?(row.after)
      :fixed
    elsif row.after == "flaky" && row.before != "flaky"
      :new_flaky
    end
  end

  def slower?(row)
    return false if row.before_ms.nil? || row.after_ms.nil?
    return false if [ row.before, row.after ].include?("skipped")
    row.after_ms >= row.before_ms * SLOWER_RATIO && row.delta_ms >= SLOWER_MIN_MS
  end
end

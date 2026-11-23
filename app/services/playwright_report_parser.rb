# Convierte la salida de `npx playwright test --reporter=json` en resultados planos.
#
# Estructura (verificada contra spec/fixtures/playwright_report.json, Playwright 1.59):
#   suites[]            una por archivo (title = ruta del archivo; no forma parte del título)
#     suites[]          describe anidados, a cualquier profundidad
#     specs[]           title, file
#       tests[]         projectName, status (expected|unexpected|flaky|skipped)
#         results[]     un elemento por intento: status, retry, duration, error, errors[]
#
# No confía en los contadores del cliente (`stats`): solo devuelve resultados individuales;
# los totales los calcula Run#recompute_counts! a partir de lo guardado.
class PlaywrightReportParser
  class ParseError < StandardError; end

  Result = Struct.new(:file, :title, :project_name, :status, :duration_ms, :retries,
                      :error_message, keyword_init: true)
  Report = Struct.new(:started_at, :duration_ms, :results, keyword_init: true)

  TITLE_SEPARATOR = " > ".freeze
  MAX_DEPTH = 50
  MAX_TESTS = 20_000
  MAX_ERROR_CHARS = 10_000
  FAILED_ATTEMPT = %w[failed timedOut interrupted].freeze
  ANSI = /\e\[[0-9;]*[A-Za-z]/

  def self.parse(json_string)
    data = JSON.parse(json_string)
    new(data).parse
  rescue JSON::ParserError => e
    raise ParseError, "JSON inválido: #{e.message.lines.first&.strip&.truncate(120)}"
  end

  def initialize(data)
    @data = data
    @results = []
  end

  def parse
    raise ParseError, "el reporte debe ser un objeto JSON" unless @data.is_a?(Hash)
    suites = @data["suites"]
    raise ParseError, "falta la lista \"suites\" del reporte de Playwright" unless suites.is_a?(Array)

    suites.each { |suite| walk(suite, [], 0) }
    raise ParseError, "el reporte no contiene pruebas" if @results.empty?

    stats = @data["stats"].is_a?(Hash) ? @data["stats"] : {}
    Report.new(started_at: parse_time(stats["startTime"]),
               duration_ms: non_negative_ms(stats["duration"]),
               results: @results)
  end

  private

  def walk(suite, path, depth)
    raise ParseError, "suite inválida: se esperaba un objeto" unless suite.is_a?(Hash)
    raise ParseError, "anidamiento de suites demasiado profundo" if depth > MAX_DEPTH

    # La suite de nivel superior representa el archivo: su título no entra en la ruta.
    title_path = depth.zero? ? path : path + [ suite["title"].to_s ]

    array(suite, "specs").each { |spec| read_spec(spec, title_path, suite["file"]) }
    array(suite, "suites").each { |child| walk(child, title_path, depth + 1) }
  end

  def read_spec(spec, title_path, suite_file)
    raise ParseError, "spec inválida: se esperaba un objeto" unless spec.is_a?(Hash)
    file = (spec["file"].presence || suite_file).to_s
    raise ParseError, "spec sin archivo" if file.blank?
    title = (title_path + [ spec["title"].to_s ]).reject(&:blank?).join(TITLE_SEPARATOR)
    raise ParseError, "spec sin título" if title.blank?

    array(spec, "tests").each do |test|
      raise ParseError, "test inválido: se esperaba un objeto" unless test.is_a?(Hash)
      raise ParseError, "el reporte supera #{MAX_TESTS} pruebas" if @results.size >= MAX_TESTS
      @results << build_result(file, title, test)
    end
  end

  def build_result(file, title, test)
    attempts = array(test, "results").select { |r| r.is_a?(Hash) }
    status = final_status(test["status"], attempts)
    Result.new(
      file: file.truncate(500), title: title, project_name: test["projectName"].to_s.truncate(100),
      status: status,
      duration_ms: non_negative_ms(attempts.sum { |r| r["duration"].is_a?(Numeric) ? [ r["duration"], 0 ].max : 0 }),
      retries: [ attempts.size - 1, 0 ].max,
      error_message: error_for(status, attempts)
    )
  end

  # Regla: una prueba cuyo último intento pasó después de un intento fallido es "flaky",
  # aunque el campo `status` del reporte diga otra cosa.
  def final_status(reported, attempts)
    last = attempts.last&.dig("status")
    return "skipped" if reported == "skipped" || last == "skipped" || (attempts.empty? && reported != "unexpected")

    retried_after_failure = attempts[0...-1].any? { |r| FAILED_ATTEMPT.include?(r["status"]) }
    return "flaky" if reported == "flaky" || (last == "passed" && retried_after_failure)

    case reported
    when "expected" then "passed"   # incluye test.fail() que falló como se esperaba
    when "unexpected" then "failed"
    else last == "passed" ? "passed" : "failed"
    end
  end

  # failed: error del último intento; flaky: error del intento que falló (el que se quiere ver).
  def error_for(status, attempts)
    source = case status
    when "failed" then attempts.reverse
    when "flaky" then attempts
    else return nil
    end
    attempt = source.find { |r| FAILED_ATTEMPT.include?(r["status"]) }
    return nil unless attempt

    messages = []
    messages << attempt.dig("error", "message") if attempt["error"].is_a?(Hash)
    if messages.compact.empty? && attempt["errors"].is_a?(Array)
      messages.concat(attempt["errors"].filter_map { |e| e["message"] if e.is_a?(Hash) })
    end
    text = messages.compact.map(&:to_s).join("\n\n").gsub(ANSI, "").strip
    text.presence&.truncate(MAX_ERROR_CHARS)
  end

  def array(node, key)
    value = node[key]
    return [] if value.nil?
    raise ParseError, "\"#{key}\" debe ser una lista" unless value.is_a?(Array)
    value
  end

  def non_negative_ms(value)
    value.is_a?(Numeric) ? [ value.round, 0 ].max.clamp(0, 2_147_483_647) : 0
  end

  def parse_time(value)
    Time.iso8601(value.to_s)
  rescue ArgumentError
    Time.current
  end
end

module ApplicationHelper
  STATUS_LABELS = { "passed" => "Pasó", "failed" => "Falló", "flaky" => "Inestable", "skipped" => "Omitida" }.freeze
  STATUS_ICONS = { "passed" => "✓", "failed" => "✕", "flaky" => "≈", "skipped" => "–" }.freeze

  def status_label(status) = STATUS_LABELS.fetch(status, status)

  # Insignia con icono + texto: el estado no depende solo del color (accesibilidad).
  def status_badge(status)
    tag.span(class: "badge badge--#{status}") do
      tag.span(STATUS_ICONS.fetch(status, "?"), aria: { hidden: true }) + " " + status_label(status)
    end
  end

  def format_duration(ms)
    ms = ms.to_i
    return "#{ms} ms" if ms < 1_000
    return "#{format('%.1f', ms / 1000.0)} s" if ms < 60_000
    "#{ms / 60_000} min #{(ms % 60_000) / 1000} s"
  end

  def short_sha(sha) = sha.to_s.first(7)

  # Mini gráfica SVG del % de éxito (sin JavaScript ni estilos en línea: compatible con la CSP).
  def pass_rate_sparkline(runs, width: 160, height: 36)
    return tag.span("—", class: "muted") if runs.size < 2
    step = width.to_f / (runs.size - 1)
    points = runs.each_with_index.map do |run, i|
      "#{(i * step).round(1)},#{(height - 2 - (run.pass_rate / 100.0) * (height - 4)).round(1)}"
    end
    last_x, last_y = points.last.split(",")
    label = "Tendencia del % de éxito en las últimas #{runs.size} ejecuciones: de #{runs.first.pass_rate}% a #{runs.last.pass_rate}%"
    tag.svg(class: "sparkline", viewBox: "0 0 #{width} #{height}", width: width, height: height,
            role: "img", aria: { label: label }) do
      tag.polyline(points: points.join(" "), class: "sparkline__line") +
        tag.circle(cx: last_x, cy: last_y, r: 3, class: "sparkline__dot")
    end
  end

  def delta_text(value, unit: "", invert: false)
    return "sin cambios" if value.to_f.zero?
    arrow = value.positive? ? "▲" : "▼"
    "#{arrow} #{value.abs}#{unit}"
  end

  def badge_color(run)
    return "#6b7280" unless run
    return "#15803d" if run.failed.zero?
    run.pass_rate >= 90 ? "#b45309" : "#c81e3a"
  end

  def upload_curl(project)
    <<~CMD.strip
      curl -X POST "#{request.base_url}/api/v1/projects/#{project.slug}/runs?branch=main" \\
        -H "Authorization: Bearer #{project.api_token}" \\
        -H "Content-Type: application/json" \\
        --data-binary @playwright-report.json
    CMD
  end
end

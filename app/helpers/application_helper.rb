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

  def upload_curl(project)
    <<~CMD.strip
      curl -X POST "#{request.base_url}/api/v1/projects/#{project.slug}/runs?branch=main" \\
        -H "Authorization: Bearer #{project.api_token}" \\
        -H "Content-Type: application/json" \\
        --data-binary @playwright-report.json
    CMD
  end
end

require "csv"

class RunsController < ApplicationController
  before_action :find_project

  STATUS_ORDER = { "failed" => 0, "flaky" => 1, "passed" => 2, "skipped" => 3 }.freeze
  CSV_HEADERS = %w[estado prueba archivo navegador reintentos duracion_ms error].freeze

  def show
    @run = @project.runs.find(params[:id]) # acotado al proyecto: no se ve una ejecución ajena
    @results = @run.test_results.to_a.sort_by { |r| [ STATUS_ORDER.fetch(r.status, 9), r.file, r.title ] }
    @previous = @run.previous

    respond_to do |format|
      format.html
      format.csv do
        send_data to_csv(@results), type: "text/csv; charset=utf-8",
                                    filename: "#{@project.slug}-ejecucion-#{@run.id}.csv"
      end
    end
  end

  private

  def to_csv(results)
    "﻿" + CSV.generate do |csv| # BOM: Excel abre bien los acentos
      csv << CSV_HEADERS
      results.each do |r|
        csv << [ r.status, r.title, r.file, r.project_name, r.retries, r.duration_ms, r.error_message ].map { |v| safe_cell(v) }
      end
    end
  end

  # Evita "CSV injection": una celda que empieza con = + - @ se ejecutaría como fórmula en Excel.
  def safe_cell(value)
    text = value.to_s
    text.match?(/\A[=+\-@\t\r]/) ? "'#{text}" : text
  end
end

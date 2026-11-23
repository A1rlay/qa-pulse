require "rails_helper"

RSpec.describe "Mejoras: comparar, insights, insignia, CSV y token", type: :request do
  let(:project) { create(:project, name: "Tienda") }
  def json = JSON.parse(response.body)
  let(:curl_ua) { { "User-Agent" => "curl/8.10.1" } }

  def make_run(at:, branch: "main", results: { "a" => "passed" })
    run = create(:run, project: project, branch: branch, started_at: Time.utc(2026, 1, 1) + at.hours)
    results.each { |title, status| create(:test_result, run: run, title: title, status: status, error_message: status == "failed" ? "boom" : nil) }
    run.recompute_counts!
    run
  end

  describe "comparar ejecuciones" do
    let!(:old_run) { make_run(at: 0, results: { "pago" => "passed", "login" => "failed" }) }
    let!(:new_run) { make_run(at: 1, results: { "pago" => "failed", "login" => "passed" }) }

    it "por defecto compara la última contra la anterior" do
      get "/projects/#{project.slug}/compare"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nuevas fallas", "Arregladas", "pago", "login")
    end

    it "acepta ejecuciones elegidas y avisa si son la misma" do
      get "/projects/#{project.slug}/compare", params: { base: new_run.id, head: new_run.id }
      expect(response.body).to include("Elegiste la misma ejecución")
    end

    it "404 si una de las ejecuciones es de otro proyecto" do
      foreign = create(:run, project: create(:project))
      get "/projects/#{project.slug}/compare", params: { base: foreign.id, head: new_run.id }
      expect(response).to have_http_status(:not_found)
    end

    it "estado vacío con menos de dos ejecuciones" do
      empty = create(:project)
      get "/projects/#{empty.slug}/compare"
      expect(response.body).to include("al menos dos ejecuciones")
    end

    it "el detalle de una ejecución enlaza a la comparación con la anterior" do
      get "/projects/#{project.slug}/runs/#{new_run.id}"
      expect(response.body).to include("/projects/#{project.slug}/compare?base=#{old_run.id}&amp;head=#{new_run.id}")
    end
  end

  describe "filtro por rama en la API" do
    before do
      make_run(at: 0, branch: "main", results: { "x" => "passed" })
      make_run(at: 1, branch: "feature", results: { "x" => "flaky" })
    end

    it "runs.json devuelve solo la rama pedida" do
      get "/api/v1/projects/#{project.slug}/runs.json", params: { branch: "main" }
      expect(json["runs"].map { |r| r["branch"] }).to eq([ "main" ])
      expect(json["branch"]).to eq("main")
    end

    it "flaky.json aplica la regla solo a la rama pedida" do
      get "/api/v1/projects/#{project.slug}/flaky.json", params: { branch: "main" }
      expect(json["tests"]).to be_empty
      get "/api/v1/projects/#{project.slug}/flaky.json", params: { branch: "feature" }
      expect(json["tests"].size).to eq(1)
    end

    it "el tablero ofrece el selector de rama cuando hay varias" do
      get "/projects/#{project.slug}"
      expect(response.body).to include('id="branch-filter"', '<option value="feature">feature</option>')
    end
  end

  describe "insights y búsqueda" do
    before { make_run(at: 0, results: { "Carrito > agrega" => "failed", "Login" => "passed" }) }

    it "insights.json trae lentas y mapa de calor" do
      get "/api/v1/projects/#{project.slug}/insights.json"
      expect(response).to have_http_status(:ok)
      expect(json.keys).to include("slowest", "heatmap", "history_url_template")
      expect(json["heatmap"]["tests"].map { |t| t["title"] }).to eq([ "Carrito > agrega" ])
    end

    it "tests.json busca y enlaza al historial" do
      get "/api/v1/projects/#{project.slug}/tests.json", params: { q: "agrega" }
      expect(json["tests"].sole).to include("title" => "Carrito > agrega", "last_status" => "failed")
      expect(json["tests"].sole["history_url"]).to match(%r{/projects/#{project.slug}/tests/\h{64}})
    end

    it "la página de insights carga" do
      get "/projects/#{project.slug}/insights"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("/api/v1/projects/#{project.slug}/insights.json", "/api/v1/projects/#{project.slug}/tests.json")
    end
  end

  describe "insignia SVG" do
    it "muestra el % de éxito, con el nombre escapado, y la puede pedir cualquier cliente" do
      project.update!(name: "<script>x</script>")
      make_run(at: 0, results: { "a" => "passed", "b" => "failed" })
      get "/projects/#{project.slug}/badge.svg", headers: curl_ua
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("image/svg+xml")
      expect(response.body).to include("50.0% · 1 ✕", "&lt;script&gt;")
      expect(response.body).not_to include("<script>")
      expect(response.headers["Cache-Control"]).to include("max-age=60")
    end

    it "sin ejecuciones dice 'sin datos'" do
      get "/projects/#{project.slug}/badge.svg", headers: curl_ua
      expect(response.body).to include("sin datos")
    end
  end

  describe "exportar CSV" do
    it "descarga los resultados y neutraliza fórmulas de Excel" do
      run = make_run(at: 0, results: { "=HYPERLINK(\"http://x\")" => "failed", "normal" => "passed" })
      get "/projects/#{project.slug}/runs/#{run.id}.csv", headers: curl_ua
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      expect(response.headers["Content-Disposition"]).to include("attachment", "#{project.slug}-ejecucion-#{run.id}.csv")
      rows = CSV.parse(response.body.delete_prefix("﻿"))
      expect(rows.first).to eq(RunsController::CSV_HEADERS)
      expect(rows.map { |r| r[1] }).to include("'=HYPERLINK(\"http://x\")", "normal")
    end
  end

  describe "regenerar token" do
    let(:report) { Rails.root.join("spec/fixtures/playwright_report.json").read }

    it "invalida el token anterior y el nuevo funciona" do
      old_token = project.api_token
      post "/projects/#{project.slug}/rotate_token"
      expect(response).to redirect_to("/projects/#{project.slug}#subir")
      new_token = project.reload.api_token
      expect(new_token).not_to eq(old_token)

      post "/api/v1/projects/#{project.slug}/runs", params: report, headers: { "Authorization" => "Bearer #{old_token}" }
      expect(response).to have_http_status(:unauthorized)
      post "/api/v1/projects/#{project.slug}/runs", params: report, headers: { "Authorization" => "Bearer #{new_token}" }
      expect(response).to have_http_status(:created)
    end

    it "exige el token CSRF del formulario" do
      ActionController::Base.allow_forgery_protection = true
      expect { post "/projects/#{project.slug}/rotate_token" }.not_to(change { project.reload.api_token })
      expect(response).to have_http_status(:unprocessable_content)
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    it "no se puede regenerar con GET" do
      get "/projects/#{project.slug}/rotate_token"
      expect(response).to have_http_status(:not_found)
    end
  end

  it "la lista de proyectos dibuja la mini gráfica de tendencia" do
    3.times { |i| make_run(at: i) }
    get "/"
    expect(response.body).to include('class="sparkline"', "Tendencia del % de éxito en las últimas 3 ejecuciones")
  end
end

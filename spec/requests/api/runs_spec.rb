require "rails_helper"

RSpec.describe "API v1 de ejecuciones", type: :request do
  let(:project) { create(:project) }
  let(:fixture) { Rails.root.join("spec/fixtures/playwright_report.json").read }
  let(:auth) { { "Authorization" => "Bearer #{project.api_token}", "Content-Type" => "application/json" } }

  def upload(body = fixture, headers: auth, query: "")
    post "/api/v1/projects/#{project.slug}/runs#{query}", params: body, headers: headers
  end

  def json = JSON.parse(response.body)

  describe "POST /api/v1/projects/:slug/runs" do
    it "201: guarda la ejecución y devuelve el resumen calculado" do
      expect { upload(query: "?branch=main&commit_sha=abc1234") }
        .to change(Run, :count).by(1).and change(TestResult, :count).by(30)
      expect(response).to have_http_status(:created)
      expect(json).to include("total" => 30, "passed" => 25, "failed" => 1, "skipped" => 1,
                              "flaky" => 3, "branch" => "main", "commit_sha" => "abc1234")
      expect(json["url"]).to end_with("/projects/#{project.slug}/runs/#{Run.last.id}")
    end

    it "ignora los conteos que manda el cliente en stats" do
      tampered = JSON.parse(fixture)
      tampered["stats"].merge!("expected" => 1000, "unexpected" => 0, "flaky" => 0)
      upload(tampered.to_json)
      expect(json.slice("total", "passed", "flaky")).to eq("total" => 30, "passed" => 25, "flaky" => 3)
    end

    it "acepta el reporte aunque curl lo mande como formulario (-d sin Content-Type)" do
      upload(headers: { "Authorization" => auth["Authorization"],
                        "Content-Type" => "application/x-www-form-urlencoded" }, query: "?branch=main")
      expect(response).to have_http_status(:created)
      expect(json).to include("total" => 30, "branch" => "main")
    end

    it "ignora branch si no es texto (strong params)" do
      upload(JSON.parse(fixture).merge("branch" => { "a" => 1 }).to_json)
      expect(response).to have_http_status(:created)
      expect(Run.last.branch).to be_nil
    end

    it "acepta branch y commit_sha en el JSON de nivel superior" do
      upload(JSON.parse(fixture).merge("branch" => "feature/x", "commit_sha" => "deadbeef").to_json)
      expect(Run.last.attributes.slice("branch", "commit_sha"))
        .to eq("branch" => "feature/x", "commit_sha" => "deadbeef")
    end

    context "401 con token inválido" do
      let(:other) { create(:project) }

      {
        "sin encabezado" => {},
        "token incorrecto" => { "Authorization" => "Bearer nope" },
        "esquema distinto de Bearer" => { "Authorization" => "Token %s" },
        "token vacío" => { "Authorization" => "Bearer " }
      }.each do |name, headers|
        it name do
          headers = headers.transform_values { |v| format(v, project.api_token) }
          expect { upload(headers: headers.merge("Content-Type" => "application/json")) }.not_to change(Run, :count)
          expect(response).to have_http_status(:unauthorized)
          expect(response.media_type).to eq("application/problem+json")
          expect(json["type"]).to end_with("/invalid-token")
        end
      end

      it "sin token y con JSON roto responde 401 (autentica antes de leer el cuerpo)" do
        upload("{\"suites\": [", headers: { "Content-Type" => "application/json" })
        expect(response).to have_http_status(:unauthorized)
      end

      it "acepta el esquema Bearer sin importar mayúsculas" do
        upload(headers: auth.merge("Authorization" => "bearer #{project.api_token}"))
        expect(response).to have_http_status(:created)
      end

      it "con el token válido de otro proyecto" do
        upload(headers: auth.merge("Authorization" => "Bearer #{other.api_token}"))
        expect(response).to have_http_status(:unauthorized)
        expect(other.runs.count + project.runs.count).to eq(0)
      end

      it "con un slug que no existe (misma respuesta, no revela qué existe)" do
        post "/api/v1/projects/no-existe/runs", params: fixture, headers: auth
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "422 con reporte malformado" do
      it "JSON roto, sin guardar nada" do
        expect { upload("{\"suites\": [") }.not_to change(Run, :count)
        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to include("status" => 422, "title" => "Reporte inválido")
      end

      it "JSON roto enviado sin Content-Type" do
        upload("{nope", headers: { "Authorization" => auth["Authorization"] })
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "un cuerpo de formulario con %-encoding inválido no provoca 500" do
        upload("100%zz&a=b", headers: { "Authorization" => auth["Authorization"],
                                         "Content-Type" => "application/x-www-form-urlencoded" })
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "JSON válido que no es un reporte de Playwright" do
        upload({ "hola" => "mundo" }.to_json)
        expect(response).to have_http_status(:unprocessable_content)
        expect(json["detail"]).to include("suites")
      end

      it "commit_sha que no es hexadecimal" do
        upload(query: "?commit_sha=%3Cscript%3E")
        expect(response).to have_http_status(:unprocessable_content)
        expect(Run.count).to eq(0)
      end

      it "a mitad de la ingesta: la transacción no deja una ejecución a medias" do
        allow(TestResult).to receive(:insert_all!).and_raise(ActiveRecord::StatementInvalid, "falla simulada")
        expect { upload rescue nil }.not_to change(Run, :count)
      end
    end

    it "413 con un reporte de más de 10 MB, antes de autenticar o parsear" do
      big = "{\"suites\": [], \"pad\": \"#{'x' * 10.megabytes}\"}"
      expect(PlaywrightReportParser).not_to receive(:parse)
      upload(big, headers: { "Content-Type" => "application/json" })
      expect(response).to have_http_status(:content_too_large)
    end
  end

  describe "GET /api/v1/projects/:slug/runs.json" do
    before do
      25.times { |i| create(:run, project: project, started_at: Time.utc(2026, 1, 1) + i.days, branch: "b#{i}") }
    end

    it "devuelve las últimas 20 en orden cronológico" do
      get "/api/v1/projects/#{project.slug}/runs.json"
      expect(response).to have_http_status(:ok)
      expect(json["runs"].map { |r| r["branch"] }).to eq((5..24).map { |i| "b#{i}" })
      expect(json["runs"].first.keys).to include("pass_rate", "failed", "flaky", "duration_ms", "started_at")
    end

    it "respeta limit y lo acota a 1..100" do
      get "/api/v1/projects/#{project.slug}/runs.json?limit=3"
      expect(json["runs"].size).to eq(3)
      get "/api/v1/projects/#{project.slug}/runs.json?limit=-5"
      expect(json["runs"].size).to eq(1)
      get "/api/v1/projects/#{project.slug}/runs.json?limit=abc"
      expect(json["runs"].size).to eq(20)
    end

    it "404 problem+json para un proyecto inexistente" do
      get "/api/v1/projects/no-existe/runs.json"
      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/problem+json")
    end
  end

  describe "GET /api/v1/projects/:slug/flaky.json" do
    it "lista las pruebas inestables con cambios, último error y enlace al historial" do
      %w[passed failed passed].each_with_index do |status, i|
        run = create(:run, project: project, started_at: Time.utc(2026, 1, 1) + i.hours)
        create(:test_result, run: run, status: status, error_message: status == "failed" ? "boom" : nil)
      end
      get "/api/v1/projects/#{project.slug}/flaky.json"
      expect(response).to have_http_status(:ok)
      test = json["tests"].sole
      expect(test).to include("flips" => 2, "flaky_runs" => 0, "last_failure_message" => "boom")
      expect(test["history_url"]).to match(%r{/projects/#{project.slug}/tests/\h{64}\z})
      expect(json["rule"]).to include("10")
    end
  end
end

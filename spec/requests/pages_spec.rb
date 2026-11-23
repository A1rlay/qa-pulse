require "rails_helper"

RSpec.describe "Páginas HTML", type: :request do
  let(:project) { create(:project, name: "Tienda") }
  let(:xss) { "<script>alert(1)</script>" }

  def expect_clean_page
    expect(response.body).not_to include("%>") # ERB mal cerrado
    expect(response.body).not_to include("translation missing")
  end

  describe "proyectos" do
    it "lista los proyectos con su token y comando curl" do
      project
      get "/"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(project.api_token, "/api/v1/projects/#{project.slug}/runs")
      expect_clean_page
    end

    it "muestra un estado vacío sin proyectos" do
      get "/"
      expect(response.body).to include("Aún no hay proyectos")
    end

    it "crea un proyecto y muestra sus instrucciones de subida" do
      post "/projects", params: { project: { name: "Mi App" } }
      expect(response).to redirect_to("/projects")
      follow_redirect!
      expect(response.body).to include("ya puede recibir reportes", Project.last.api_token)
    end

    it "ignora atributos no permitidos (strong params)" do
      post "/projects", params: { project: { name: "Mi App", api_token: "a" * 64, slug: "otro" } }
      expect(Project.last.api_token).not_to eq("a" * 64)
      expect(Project.last.slug).to eq("mi-app")
    end

    it "422 con mensajes en español si falta el nombre" do
      post "/projects", params: { project: { name: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Nombre no puede estar vacío")
    end

    it "rechaza un formulario sin token CSRF" do
      ActionController::Base.allow_forgery_protection = true
      post "/projects", params: { project: { name: "Sin CSRF" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(Project.count).to eq(0)
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    it "el formulario incluye el token CSRF" do
      ActionController::Base.allow_forgery_protection = true
      get "/"
      expect(response.body).to include('name="authenticity_token"', 'name="csrf-token"')
    ensure
      ActionController::Base.allow_forgery_protection = false
    end
  end

  describe "tablero" do
    it "renderiza la última ejecución y las URLs de AJAX" do
      run = create(:run, project: project, branch: xss)
      create(:test_result, run: run, status: "failed")
      run.recompute_counts!
      get "/projects/#{project.slug}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("/api/v1/projects/#{project.slug}/runs.json?limit=20",
                                        "/api/v1/projects/#{project.slug}/flaky.json")
      expect(response.body).not_to include(xss)
      expect(response.body).to include("&lt;script&gt;alert(1)&lt;/script&gt;")
      expect_clean_page
    end

    it "funciona sin ejecuciones" do
      get "/projects/#{project.slug}"
      expect(response).to have_http_status(:ok)
    end

    it "404 para un proyecto inexistente" do
      get "/projects/no-existe"
      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("No encontramos")
    end

    it "envía una política CSP estricta (sin unsafe-inline)" do
      get "/projects/#{project.slug}"
      csp = response.headers["Content-Security-Policy"]
      expect(csp).to include("script-src 'self' 'nonce-", "object-src 'none'")
      expect(csp).not_to include("unsafe-inline")
    end
  end

  describe "detalle de ejecución" do
    let(:run) { create(:run, project: project) }

    before do
      create(:test_result, run: run, title: "Carrito > #{xss}", status: "failed", error_message: "Error: #{xss}")
      create(:test_result, run: run, title: "Carrito > ok", status: "passed")
      run.recompute_counts!
    end

    it "muestra los resultados con los datos del reporte escapados" do
      get "/projects/#{project.slug}/runs/#{run.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(xss)
      expect(response.body.scan("&lt;script&gt;alert(1)&lt;/script&gt;").size).to eq(2)
      expect(response.body).to include('data-status="failed"', 'data-status="passed"', "Ver error")
      expect_clean_page
    end

    it "no deja ver una ejecución de otro proyecto con la URL de este" do
      other = create(:run, project: create(:project))
      get "/projects/#{project.slug}/runs/#{other.id}"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "historial de prueba" do
    it "muestra hasta 20 resultados, del más antiguo al más reciente" do
      25.times do |i|
        run = create(:run, project: project, started_at: Time.utc(2026, 1, 1) + i.hours)
        create(:test_result, run: run, status: i.even? ? "passed" : "failed", duration_ms: 100 + i)
      end
      key = TestResult.last.test_key
      get "/projects/#{project.slug}/tests/#{key}"
      expect(response).to have_http_status(:ok)
      expect(response.body.scan('class="strip__cell').size).to eq(20)
      expect(response.body).to include("Esta prueba es <strong>inestable</strong>")
      expect_clean_page
    end

    it "404 para una prueba que no pertenece al proyecto" do
      run = create(:run, project: create(:project))
      result = create(:test_result, run: run)
      get "/projects/#{project.slug}/tests/#{result.test_key}"
      expect(response).to have_http_status(:not_found)
    end
  end
end

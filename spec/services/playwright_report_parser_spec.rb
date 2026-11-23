require "rails_helper"

RSpec.describe PlaywrightReportParser do
  let(:fixture) { Rails.root.join("spec/fixtures/playwright_report.json").read }
  let(:report) { described_class.parse(fixture) }
  let(:by_title) { report.results.index_by(&:title) }

  # Reporte mínimo con la misma forma que el de Playwright.
  def report_with(tests, suites: nil)
    spec = { "title" => "caso", "file" => "a.spec.ts", "tests" => tests }
    { "suites" => suites || [ { "title" => "a.spec.ts", "file" => "a.spec.ts", "specs" => [ spec ] } ],
      "stats" => { "startTime" => "2026-01-01T00:00:00Z", "duration" => 12.6 } }.to_json
  end

  def attempt(status, duration: 10, error: nil)
    { "status" => status, "duration" => duration, "retry" => 0 }
      .merge(error ? { "error" => { "message" => error } } : {})
  end

  describe "con el reporte real de Playwright (fixture)" do
    it "encuentra las 30 pruebas" do
      expect(report.results.size).to eq(30)
    end

    it "calcula los conteos por estado a partir de los resultados" do
      expect(report.results.map(&:status).tally)
        .to eq("passed" => 25, "flaky" => 3, "failed" => 1, "skipped" => 1)
    end

    it "marca como flaky las pruebas que pasaron tras un reintento fallido" do
      flaky = report.results.select { |r| r.status == "flaky" }.map(&:title)
      expect(flaky).to contain_exactly(
        "Autenticación > cierra sesión por inactividad",
        "Catálogo > Filtros > filtra por rango de precio",
        "Carrito > actualiza el contador del ícono"
      )
      expect(by_title["Carrito > actualiza el contador del ícono"].retries).to eq(1)
    end

    it "arma el título completo con los describe anidados, sin el nombre del archivo" do
      r = by_title.fetch("Checkout > Pago > rechaza una tarjeta vencida")
      expect([ r.file, r.project_name ]).to eq(%w[checkout.spec.ts chromium])
      expect(by_title).to have_key("Autenticación > Recuperar contraseña > envía el correo de recuperación")
    end

    it "guarda el error sin códigos ANSI y con la regresión agotando los reintentos" do
      failed = by_title.fetch("Checkout > aplica un cupón de descuento")
      expect([ failed.status, failed.retries ]).to eq([ "failed", 2 ])
      expect(failed.error_message).to include("Expected: \"$268.20\"")
      expect(failed.error_message).not_to include("\e[")
    end

    it "a las flaky les guarda el error del intento que falló y a las verdes ninguno" do
      expect(by_title["Autenticación > cierra sesión por inactividad"].error_message).to include("Sesión expirada")
      expect(by_title["Carrito > agrega un producto"].error_message).to be_nil
    end

    it "toma la fecha y duración de stats" do
      expect(report.started_at).to eq(Time.iso8601("2026-11-23T00:11:43.024Z"))
      expect(report.duration_ms).to eq(7808)
    end
  end

  describe "reglas de estado" do
    it "es flaky si el último intento pasó tras uno fallido aunque status diga expected" do
      r = described_class.parse(report_with([ { "projectName" => "x", "status" => "expected",
        "results" => [ attempt("timedOut", error: "timeout"), attempt("passed") ] } ])).results.first
      expect([ r.status, r.retries, r.error_message ]).to eq([ "flaky", 1, "timeout" ])
    end

    it "unexpected es failed y suma la duración de todos los intentos" do
      r = described_class.parse(report_with([ { "projectName" => "x", "status" => "unexpected",
        "results" => [ attempt("failed", duration: 5.4), attempt("failed", duration: 5.4) ] } ])).results.first
      expect([ r.status, r.duration_ms ]).to eq([ "failed", 11 ])
    end

    it "test.fail() que falló como se esperaba cuenta como passed" do
      r = described_class.parse(report_with([ { "projectName" => "x", "status" => "expected",
        "expectedStatus" => "failed", "results" => [ attempt("failed") ] } ])).results.first
      expect(r.status).to eq("passed")
    end

    it "separa la misma prueba en dos navegadores" do
      tests = %w[chromium firefox].map { |p| { "projectName" => p, "status" => "expected", "results" => [ attempt("passed") ] } }
      expect(described_class.parse(report_with(tests)).results.map(&:project_name)).to eq(%w[chromium firefox])
    end
  end

  describe "anidamiento" do
    it "recorre suites a cualquier profundidad" do
      leaf = { "title" => "hoja", "file" => "a.spec.ts",
               "tests" => [ { "projectName" => "x", "status" => "expected", "results" => [ attempt("passed") ] } ] }
      inner = (1..5).reverse_each.reduce({ "title" => "n6", "specs" => [ leaf ] }) do |child, n|
        { "title" => "n#{n}", "suites" => [ child ] }
      end
      top = [ { "title" => "a.spec.ts", "file" => "a.spec.ts", "suites" => [ inner ] } ]
      expect(described_class.parse(report_with([], suites: top)).results.first.title)
        .to eq("n1 > n2 > n3 > n4 > n5 > n6 > hoja")
    end

    it "rechaza anidamientos absurdos en lugar de agotar la pila" do
      deep = (1..60).reduce({ "title" => "x" }) { |child, n| { "title" => "s#{n}", "suites" => [ child ] } }
      # El parser corta en MAX_DEPTH aunque reciba el hash ya parseado...
      expect { described_class.new("suites" => [ deep ]).parse }
        .to raise_error(described_class::ParseError, /profundo/)
      # ...y JSON.parse (max_nesting 100) lo corta antes cuando llega como texto.
      body = JSON.generate({ "suites" => [ deep ] }, max_nesting: false)
      expect { described_class.parse(body) }.to raise_error(described_class::ParseError, /JSON inválido/)
    end
  end

  describe "entradas inválidas" do
    {
      "JSON roto" => "{\"suites\": [",
      "arreglo en la raíz" => "[]",
      "sin suites" => { "stats" => {} }.to_json,
      "suites no es lista" => { "suites" => "x" }.to_json,
      "suite no es objeto" => { "suites" => [ 1 ] }.to_json,
      "sin pruebas" => { "suites" => [] }.to_json,
      "cuerpo vacío" => ""
    }.each do |name, body|
      it "lanza ParseError: #{name}" do
        expect { described_class.parse(body) }.to raise_error(described_class::ParseError)
      end
    end
  end
end

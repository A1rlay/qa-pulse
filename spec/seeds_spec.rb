require "rails_helper"

RSpec.describe "db/seeds.rb" do
  def load_seeds = expect { load Rails.root.join("db/seeds.rb") }.to output(/Tienda Demo/).to_stdout

  it "se puede ejecutar dos veces y cuenta la historia de la demo" do
    2.times { load_seeds }
    project = Project.find_by!(slug: "tienda-demo")
    expect(project.runs.count).to eq(15)
    expect(TestResult.count).to eq(450)

    flaky = FlakyDetector.new(project).call.map(&:title)
    expect(flaky).to contain_exactly(
      "Autenticación > cierra sesión por inactividad",
      "Catálogo > Filtros > filtra por rango de precio",
      "Carrito > actualiza el contador del ícono"
    )
    expect(project.latest_run.failed).to eq(1) # la regresión del cupón
  end

  it "usa las mismas identidades de prueba que el reporte de la demo en vivo" do
    load_seeds
    report = PlaywrightReportParser.parse(Rails.root.join("spec/fixtures/playwright_report.json").read)
    fixture_keys = report.results.map { |r| TestResult.key_for(r.file, r.title, r.project_name) }
    expect(TestResult.distinct.pluck(:test_key)).to match_array(fixture_keys)
  end
end

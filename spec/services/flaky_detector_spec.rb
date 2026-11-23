require "rails_helper"

RSpec.describe FlakyDetector do
  let(:project) { create(:project) }

  # Crea una ejecución por letra (la más antigua primero) para la prueba +title+.
  # P = passed, F = failed, K = flaky, S = skipped.
  def history(title, pattern, error: "Error: boom")
    map = { "P" => "passed", "F" => "failed", "K" => "flaky", "S" => "skipped" }
    pattern.chars.each_with_index do |code, i|
      run = project.runs.find_or_create_by!(started_at: Time.utc(2026, 1, 1) + i.hours)
      status = map.fetch(code)
      create(:test_result, run: run, title: title, status: status,
             error_message: (%w[failed flaky].include?(status) ? "#{error} ##{i}" : nil))
    end
  end

  def titles(**opts) = described_class.new(project, **opts).call.map(&:title)

  it "marca una prueba que Playwright reportó como flaky en alguna ejecución" do
    history("una vez flaky", "PPPKPP")
    expect(titles).to eq([ "una vez flaky" ])
  end

  it "marca una prueba que cambió entre passed y failed al menos 2 veces" do
    history("dos cambios", "PPFPPP")
    entry = described_class.new(project).call.first
    expect(entry.flips).to eq(2)
    expect(entry.last_failure_message).to eq("Error: boom #2")
  end

  it "no marca una regresión (un solo cambio de estado)" do
    history("regresión", "PPPPFFF")
    expect(titles).to be_empty
  end

  it "no marca pruebas siempre verdes, siempre rojas ni omitidas" do
    history("verde", "PPPPPP")
    history("rojo", "FFFFFF")
    history("omitida", "SSSSSS")
    expect(titles).to be_empty
  end

  it "ignora las omitidas al contar cambios: P S F S P son 2 cambios" do
    history("con skips", "PSFSP")
    expect(described_class.new(project).call.first.flips).to eq(2)
  end

  it "solo mira las últimas N ejecuciones" do
    history("viejo flaky", "KPFP" + "P" * 10) # la inestabilidad quedó fuera de la ventana de 10
    expect(titles).to be_empty
    expect(titles(window: 14)).to eq([ "viejo flaky" ])
  end

  it "ordena por puntuación (ejecuciones flaky + cambios)" do
    history("poco", "PPPKPP")
    history("mucho", "PFPFPF")
    expect(titles).to eq(%w[mucho poco])
  end

  it "trata la misma prueba en otro navegador como otra prueba" do
    history("misma", "PPPPPP")
    project.runs.order(:started_at).each_with_index do |run, i|
      create(:test_result, run: run, title: "misma", project_name: "firefox",
             status: i.even? ? "passed" : "failed")
    end
    expect(described_class.new(project).call.map(&:project_name)).to eq([ "firefox" ])
  end

  it "no mezcla historiales de otros proyectos" do
    other = create(:project)
    run = create(:run, project: other)
    create(:test_result, run: run, title: "ajena", status: "flaky")
    history("propia", "PPP")
    expect(titles).to be_empty
  end
end

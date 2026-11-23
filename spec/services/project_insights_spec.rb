require "rails_helper"

RSpec.describe ProjectInsights do
  let(:project) { create(:project) }

  def run_with(statuses, branch: "main", at: 0)
    run = create(:run, project: project, branch: branch, started_at: Time.utc(2026, 1, 1) + at.hours)
    statuses.each { |title, (status, ms)| create(:test_result, run: run, title: title, status: status, duration_ms: ms || 100) }
    run
  end

  it "ordena las más lentas por duración promedio e ignora las omitidas" do
    run_with({ "lenta" => [ "passed", 3000 ], "rápida" => [ "passed", 10 ], "omitida" => [ "skipped", 99_999 ] }, at: 0)
    run_with({ "lenta" => [ "passed", 1000 ], "rápida" => [ "passed", 30 ] }, at: 1)
    slowest = described_class.new(project).slowest
    expect(slowest.map { |t| t[:title] }).to eq(%w[lenta rápida])
    expect(slowest.first).to include(avg_ms: 2000, max_ms: 3000, runs: 2)
  end

  it "arma el mapa de calor solo con pruebas problemáticas, con nil donde no existían" do
    r1 = run_with({ "estable" => [ "passed" ], "rota" => [ "passed" ] }, at: 0)
    r2 = run_with({ "estable" => [ "passed" ], "rota" => [ "failed" ], "nueva" => [ "flaky" ] }, at: 1)
    heat = described_class.new(project).heatmap
    expect(heat[:runs].map { |r| r[:id] }).to eq([ r1.id, r2.id ])
    rows = heat[:tests].index_by { |t| t[:title] }
    expect(rows.keys).to contain_exactly("rota", "nueva")
    expect(rows["rota"][:statuses]).to eq(%w[passed failed])
    expect(rows["nueva"][:statuses]).to eq([ nil, "flaky" ])
  end

  it "filtra por rama" do
    run_with({ "x" => [ "failed" ] }, branch: "feature", at: 0)
    run_with({ "x" => [ "passed" ] }, branch: "main", at: 1)
    expect(described_class.new(project, branch: "main").heatmap[:tests]).to be_empty
    expect(described_class.new(project, branch: "feature").heatmap[:tests].size).to eq(1)
  end

  it "devuelve estructuras vacías sin ejecuciones" do
    insights = described_class.new(project)
    expect(insights.slowest).to eq([])
    expect(insights.heatmap).to eq(runs: [], tests: [])
  end
end

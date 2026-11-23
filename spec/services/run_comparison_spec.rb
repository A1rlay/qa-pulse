require "rails_helper"

RSpec.describe RunComparison do
  let(:project) { create(:project) }
  let(:base) { create(:run, project: project, started_at: Time.utc(2026, 1, 1)) }
  let(:head) { create(:run, project: project, started_at: Time.utc(2026, 1, 2)) }

  def result(run, title, status, ms = 100)
    create(:test_result, run: run, title: title, status: status, duration_ms: ms,
           error_message: status == "failed" ? "boom #{title}" : nil)
  end

  def titles(comparison, category) = comparison.public_send(category).map(&:title)

  it "clasifica cada prueba según cómo cambió" do
    result(base, "se rompió", "passed");     result(head, "se rompió", "failed")
    result(base, "era flaky y falla", "flaky"); result(head, "era flaky y falla", "failed")
    result(base, "arreglada", "failed");     result(head, "arreglada", "passed")
    result(base, "arreglada a medias", "failed"); result(head, "arreglada a medias", "flaky")
    result(base, "ahora flaky", "passed");   result(head, "ahora flaky", "flaky")
    result(base, "sigue rota", "failed");    result(head, "sigue rota", "failed")
    result(base, "igual", "passed");         result(head, "igual", "passed")
    result(base, "sigue flaky", "flaky");    result(head, "sigue flaky", "flaky")
    result(base, "borrada", "passed")
    result(head, "nueva y rota", "failed")
    result(head, "nueva", "passed")

    c = described_class.new(base, head)
    expect(titles(c, :new_failures)).to contain_exactly("se rompió", "era flaky y falla", "nueva y rota")
    expect(titles(c, :fixed)).to contain_exactly("arreglada", "arreglada a medias")
    expect(titles(c, :new_flaky)).to eq([ "ahora flaky" ])
    expect(titles(c, :still_failing)).to eq([ "sigue rota" ])
    expect(titles(c, :added)).to contain_exactly("nueva")
    expect(titles(c, :removed)).to eq([ "borrada" ])
    expect(c.new_failures.find { |r| r.title == "se rompió" }.error_message).to eq("boom se rompió")
  end

  it "una prueba nueva que falla cuenta como nueva falla, no solo como agregada" do
    result(head, "nueva y rota", "failed")
    c = described_class.new(base, head)
    expect(titles(c, :new_failures)).to eq([ "nueva y rota" ])
    expect(titles(c, :added)).to be_empty
  end

  it "detecta las más lentas con umbral relativo y absoluto" do
    result(base, "mucho más lenta", "passed", 1000); result(head, "mucho más lenta", "passed", 2000)
    result(base, "ruido rápido", "passed", 10);      result(head, "ruido rápido", "passed", 100)  # +900 % pero solo 90 ms
    result(base, "poco más lenta", "passed", 1000);  result(head, "poco más lenta", "passed", 1300) # +30 %
    result(base, "omitida", "skipped", 0);           result(head, "omitida", "passed", 5000)
    expect(described_class.new(base, head).slower.map(&:title)).to eq([ "mucho más lenta" ])
  end

  it "resume la variación del % de éxito y la duración" do
    base.update!(duration_ms: 1000); head.update!(duration_ms: 1500)
    result(base, "a", "passed"); result(head, "a", "failed")
    [ base, head ].each(&:recompute_counts!)
    summary = described_class.new(base, head).summary
    expect(summary).to include(pass_rate_delta: -100.0, duration_delta_ms: 500)
    expect(summary[:counts]).to include(new_failures: 1)
  end

  it "no compara ejecuciones de proyectos distintos" do
    other = create(:run, project: create(:project))
    expect { described_class.new(base, other) }.to raise_error(ArgumentError)
  end
end

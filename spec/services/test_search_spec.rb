require "rails_helper"

RSpec.describe TestSearch do
  let(:project) { create(:project) }
  let!(:run1) { create(:run, project: project, started_at: Time.utc(2026, 1, 1)) }
  let!(:run2) { create(:run, project: project, started_at: Time.utc(2026, 1, 2)) }

  before do
    create(:test_result, run: run1, title: "Carrito > agrega un producto", file: "carrito.spec.ts", status: "failed")
    create(:test_result, run: run2, title: "Carrito > agrega un producto", file: "carrito.spec.ts", status: "passed")
    create(:test_result, run: run2, title: "Checkout > aplica 100% de descuento", file: "checkout.spec.ts")
    create(:test_result, run: run2, title: "Login_rápido", file: "auth.spec.ts")
  end

  def titles(q) = described_class.new(project, q).call.map { |t| t[:title] }

  it "encuentra por título o archivo y devuelve el último estado" do
    result = described_class.new(project, "carrito").call.sole
    expect(result).to include(title: "Carrito > agrega un producto", last_status: "passed", last_run_id: run2.id, runs: 2)
    expect(titles("checkout.spec")).to eq([ "Checkout > aplica 100% de descuento" ])
  end

  it "trata % y _ como texto, no como comodines de LIKE" do
    expect(titles("0%")).to eq([ "Checkout > aplica 100% de descuento" ])
    expect(titles("%%")).to be_empty
    expect(titles("agrega_un")).to be_empty # sin escapar, "_" coincidiría con el espacio de "agrega un"
    expect(titles("Login_")).to eq([ "Login_rápido" ])
  end

  it "no se rompe con comillas ni SQL en la búsqueda" do
    expect(titles("' OR 1=1 --")).to be_empty
    expect(TestResult.count).to eq(4)
  end

  it "exige al menos 2 caracteres" do
    expect(titles("c")).to be_empty
  end

  it "no devuelve pruebas de otros proyectos" do
    other_run = create(:run, project: create(:project))
    create(:test_result, run: other_run, title: "Carrito > ajeno")
    expect(titles("ajeno")).to be_empty
  end
end

require "rails_helper"

RSpec.describe TestResult do
  it "deriva la identidad de archivo + título + proyecto de Playwright" do
    a = create(:test_result, project_name: "chromium")
    b = create(:test_result, project_name: "firefox")
    expect(a.test_key).to eq(TestResult.key_for(a.file, a.title, "chromium"))
    expect(a.test_key).not_to eq(b.test_key)
  end

  it "distingue títulos que solo difieren en mayúsculas (la colación de MySQL no)" do
    expect(TestResult.key_for("a.spec.ts", "Carrito > Agrega", "chromium"))
      .not_to eq(TestResult.key_for("a.spec.ts", "Carrito > agrega", "chromium"))
  end

  it "no confunde los límites entre campos" do
    expect(TestResult.key_for("a", "bc", "")).not_to eq(TestResult.key_for("ab", "c", ""))
  end
end

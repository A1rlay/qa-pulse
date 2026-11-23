require "rails_helper"

RSpec.describe Project do
  it "genera slug único y token de 64 caracteres al crearse" do
    a = create(:project, name: "Tienda Demo")
    b = create(:project, name: "Tienda Demo")
    expect([ a.slug, b.slug ]).to eq(%w[tienda-demo tienda-demo-2])
    expect(a.api_token).to match(/\A\h{64}\z/)
    expect(a.api_token).not_to eq(b.api_token)
  end

  it "valida el token del encabezado" do
    project = create(:project)
    expect(project.valid_token?(project.api_token)).to be(true)
    expect(project.valid_token?(project.api_token.succ)).to be(false)
    expect(project.valid_token?(nil)).to be(false)
    expect(project.valid_token?("")).to be(false)
  end
end

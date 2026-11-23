require "rails_helper"

RSpec.describe Run do
  it "recalcula los totales a partir de los resultados guardados" do
    run = create(:run, total: 999, passed: 999)
    %w[passed passed failed skipped flaky].each_with_index do |status, i|
      create(:test_result, run: run, status: status, title: "T #{i}")
    end
    run.recompute_counts!
    expect(run.reload.attributes.slice("total", "passed", "failed", "skipped", "flaky"))
      .to eq("total" => 5, "passed" => 2, "failed" => 1, "skipped" => 1, "flaky" => 1)
    expect(run.pass_rate).to eq(75.0) # (2 passed + 1 flaky) / 4 ejecutadas
  end

  it "la base de datos rechaza totales que no cuadran aunque se salten las validaciones" do
    run = create(:run)
    expect { run.update_columns(total: 3, passed: 1) }
      .to raise_error(ActiveRecord::StatementInvalid, /runs_total_matches/)
  end

  it "la base de datos rechaza un estado desconocido" do
    result = create(:test_result)
    expect { result.update_column(:status, "timedOut") }
      .to raise_error(ActiveRecord::StatementInvalid, /test_results_status_valid/)
  end
end

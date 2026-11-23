class RunsController < ApplicationController
  before_action :find_project

  STATUS_ORDER = { "failed" => 0, "flaky" => 1, "passed" => 2, "skipped" => 3 }.freeze

  def show
    @run = @project.runs.find(params[:id]) # acotado al proyecto: no se ve una ejecución ajena
    @results = @run.test_results.to_a.sort_by { |r| [ STATUS_ORDER.fetch(r.status, 9), r.file, r.title ] }
  end
end

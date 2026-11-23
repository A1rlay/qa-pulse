class TestHistoriesController < ApplicationController
  HISTORY_SIZE = 20

  before_action :find_project

  def show
    @results = TestResult.joins(:run).includes(:run)
                         .where(runs: { project_id: @project.id }, test_key: params[:test_key])
                         .order("runs.started_at DESC, runs.id DESC").limit(HISTORY_SIZE).to_a.reverse
    raise ActiveRecord::RecordNotFound if @results.empty?

    @test = @results.last
    @max_duration = [ @results.map(&:duration_ms).max.to_i, 1 ].max
    @flaky_entry = FlakyDetector.new(@project).call.find { |e| e.test_key == params[:test_key] }
  end
end

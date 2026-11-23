module Api
  module V1
    class TestsController < BaseController
      before_action :find_project!

      # GET /api/v1/projects/:slug/tests.json?q=carrito — búsqueda por título o archivo.
      def index
        tests = TestSearch.new(@project, params[:q]).call
        render json: {
          query: params[:q].to_s.first(TestSearch::MAX_LENGTH),
          tests: tests.map { |t| t.merge(history_url: project_test_history_path(@project, t[:test_key])) }
        }
      end
    end
  end
end

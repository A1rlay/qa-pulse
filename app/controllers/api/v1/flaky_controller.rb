module Api
  module V1
    class FlakyController < BaseController
      before_action :find_project!

      # GET /api/v1/projects/:slug/flaky.json?window=10 — pruebas ordenadas por inestabilidad.
      def show
        window = (Integer(params[:window].to_s, 10, exception: false) || FlakyDetector::DEFAULT_WINDOW).clamp(1, 100)
        branch = params[:branch].presence&.to_s
        tests = FlakyDetector.new(@project, window: window, branch: branch).call
        render json: {
          window: window, branch: branch,
          rule: "Inestable si en las últimas #{window} ejecuciones fue marcada flaky al menos una vez " \
                "o cambió entre passed y failed al menos #{FlakyDetector::MIN_FLIPS} veces.",
          tests: tests.map { |t| t.as_json.merge(history_url: project_test_history_path(@project, t.test_key)) }
        }
      end
    end
  end
end

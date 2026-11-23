module Api
  module V1
    class InsightsController < BaseController
      before_action :find_project!

      # GET /api/v1/projects/:slug/insights.json?window=20&branch=main
      def show
        window = Integer(params[:window].to_s, 10, exception: false) || ProjectInsights::DEFAULT_WINDOW
        insights = ProjectInsights.new(@project, window: window, branch: params[:branch].presence&.to_s)
        # La ruta exige 64 hex: se genera con un marcador válido y se reemplaza por TEST_KEY para el cliente.
        placeholder = "0" * 64
        template = project_test_history_path(@project, placeholder).sub(placeholder, "TEST_KEY")
        render json: insights.as_json.merge(history_url_template: template)
      end
    end
  end
end

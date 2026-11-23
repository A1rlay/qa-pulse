module Api
  module V1
    # La API hereda de ActionController::API: no incluye protección CSRF (no usa cookies de sesión),
    # se autentica con token Bearer. Las vistas HTML siguen protegidas por ApplicationController.
    # Errores en formato RFC 9457 (application/problem+json); catálogo en docs/build/contracts/errors.md.
    class BaseController < ActionController::API
      wrap_parameters false # no envolver ni parsear el cuerpo como params

      PROBLEM_BASE = "https://qa-pulse.local/problems/".freeze

      rescue_from ActiveRecord::RecordNotFound do
        problem(:not_found, "not-found", "No encontrado", "El proyecto no existe.")
      end
      rescue_from ActionDispatch::Http::Parameters::ParseError, ActionController::BadRequest do
        problem(:unprocessable_content, "invalid-report", "Reporte inválido", "El cuerpo no es JSON válido.")
      end

      private

      def problem(status, type, title, detail)
        code = Rack::Utils.status_code(status)
        render json: { type: PROBLEM_BASE + type, title: title, status: code, detail: detail },
               status: code, content_type: "application/problem+json"
      end

      def find_project!
        @project = Project.find_by!(slug: params[:slug].to_s)
      end
    end
  end
end

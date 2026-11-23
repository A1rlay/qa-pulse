module Api
  module V1
    class RunsController < BaseController
      MAX_UPLOAD_BYTES = 10.megabytes
      DEFAULT_LIMIT = 20

      before_action :reject_oversized_upload, only: :create
      before_action :authenticate_upload!, only: :create
      before_action :find_project!, only: :index

      # GET /api/v1/projects/:slug/runs.json?limit=20 — orden cronológico (más antigua primero).
      def index
        limit = (Integer(params[:limit].to_s, 10, exception: false) || DEFAULT_LIMIT).clamp(1, 100)
        runs = @project.recent_runs(limit).to_a.reverse
        render json: { project: { name: @project.name, slug: @project.slug },
                       runs: runs.map(&:summary) }
      end

      # POST /api/v1/projects/:slug/runs  (Authorization: Bearer <api_token>)
      # Cuerpo: salida cruda de `npx playwright test --reporter=json`, con cualquier Content-Type.
      # branch y commit_sha opcionales, en la query string o en el JSON de nivel superior.
      # El cuerpo se lee de raw_post y se parsea una sola vez aquí: nunca vía `params`,
      # para que un cuerpo malformado no se procese antes de autenticar.
      def create
        data = parse_body
        meta = run_params(data)
        if meta[:branch].to_s.length > 255
          return problem(:unprocessable_content, "invalid-params", "Parámetros inválidos", "branch admite hasta 255 caracteres.")
        end
        if meta[:commit_sha].present? && meta[:commit_sha] !~ /\A\h{7,64}\z/
          return problem(:unprocessable_content, "invalid-params", "Parámetros inválidos", "commit_sha debe ser hexadecimal (7 a 64 caracteres).")
        end

        report = PlaywrightReportParser.new(data).parse
        run = RunIngestor.new(@project, report, branch: meta[:branch], commit_sha: meta[:commit_sha]).call
        render json: run.summary.merge(url: project_run_url(@project, run)), status: :created
      rescue PlaywrightReportParser::ParseError => e
        problem(:unprocessable_content, "invalid-report", "Reporte inválido", e.message)
      end

      private

      def parse_body
        JSON.parse(request.raw_post)
      rescue JSON::ParserError => e
        raise PlaywrightReportParser::ParseError, "JSON inválido: #{e.message.lines.first.to_s.strip.truncate(120)}"
      end

      # Strong params sobre la query string + las claves de nivel superior del reporte.
      def run_params(data)
        top_level = data.is_a?(Hash) ? data.slice("branch", "commit_sha") : {}
        ActionController::Parameters.new(top_level.merge(request.query_parameters))
                                    .permit(:branch, :commit_sha).to_h.symbolize_keys
      end

      def reject_oversized_upload
        size = request.content_length || request.raw_post.bytesize
        return if size <= MAX_UPLOAD_BYTES
        problem(:content_too_large, "payload-too-large", "Reporte demasiado grande",
                "El reporte pesa #{size} bytes; el máximo es #{MAX_UPLOAD_BYTES} (10 MB).")
      end

      # Proyecto inexistente y token incorrecto responden igual (401) para no revelar qué slugs existen.
      def authenticate_upload!
        token = request.authorization.to_s[/\ABearer\s+(\S+)\s*\z/i, 1] # el esquema no distingue mayúsculas (RFC 9110)
        @project = Project.find_by(slug: request.path_parameters[:slug].to_s)
        return if @project&.valid_token?(token)
        response.headers["WWW-Authenticate"] = 'Bearer realm="qa-pulse"'
        problem(:unauthorized, "invalid-token", "Token inválido",
                "Envía el encabezado Authorization: Bearer <api_token> del proyecto.")
      end
    end
  end
end

# Para POST /api/v1/projects/:slug/runs, el cuerpo es un reporte de Playwright que el
# controlador parsea una sola vez desde raw_post. Este middleware evita que Rails lo
# interprete antes como params (JSON o formulario): así un cuerpo malformado no puede
# fallar antes de autenticar, no se parsea dos veces y no se vuelca completo en el log.
class RawReportBody
  UPLOAD_PATH = %r{\A/api/v1/projects/[^/]+/runs(?:\.json)?\z}

  def initialize(app)
    @app = app
  end

  def call(env)
    if env["REQUEST_METHOD"] == "POST" && env["PATH_INFO"].to_s.match?(UPLOAD_PATH)
      env["CONTENT_TYPE"] = "application/octet-stream"
    end
    @app.call(env)
  end
end

class ApplicationController < ActionController::Base
  # Las vistas HTML usan protección CSRF (ActionController::Base la activa por defecto: cada
  # formulario lleva un authenticity_token). La API (Api::V1::BaseController) no la usa: se
  # autentica con token Bearer.
  protect_from_forgery with: :exception

  # Solo navegadores modernos (importmap, CSS :has…) para las páginas HTML. La insignia SVG y el CSV
  # los piden herramientas que no son navegadores (el proxy de imágenes de GitHub, curl).
  allow_browser versions: :modern, if: -> { request.format.html? }

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  rescue_from ActiveRecord::RecordNotFound do
    render "errors/not_found", status: :not_found
  end

  private

  def find_project
    @project = Project.find_by!(slug: params[:project_slug] || params[:slug])
  end
end

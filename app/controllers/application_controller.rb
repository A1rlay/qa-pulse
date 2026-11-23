class ApplicationController < ActionController::Base
  # Las vistas HTML usan protección CSRF (ActionController::Base la activa por defecto: cada
  # formulario lleva un authenticity_token). La API (Api::V1::BaseController) no la usa: se
  # autentica con token Bearer.
  protect_from_forgery with: :exception

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

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

class ProjectsController < ApplicationController
  COMPARE_CHOICES = 50

  before_action :find_project, except: %i[index create]

  def index
    @projects = Project.order(:name).to_a
    @latest_runs = Run.where(id: Run.group(:project_id).select("MAX(id)")).index_by(&:project_id)
    @trends = Run.where(project_id: @projects.map(&:id))
                 .where("runs.id IN (SELECT id FROM (SELECT id, ROW_NUMBER() OVER (PARTITION BY project_id ORDER BY started_at DESC, id DESC) AS n FROM runs) ranked WHERE n <= 15)")
                 .order(:started_at, :id).group_by(&:project_id)
    @new_project = Project.new
    @created = @projects.find { |p| p.slug == flash[:created_slug] }
  end

  def show
    @latest_run = @project.latest_run
    @branches = @project.branches
  end

  def create
    @new_project = Project.new(project_params)
    if @new_project.save
      redirect_to projects_path, notice: "Proyecto «#{@new_project.name}» creado.",
                                 flash: { created_slug: @new_project.slug }
    else
      @projects = Project.order(:name).to_a
      @latest_runs = {}
      @trends = {}
      render :index, status: :unprocessable_content
    end
  end

  def insights
    @branches = @project.branches
  end

  # GET /projects/:slug/compare?base=ID&head=ID (por defecto: la última contra la anterior)
  def compare
    @choices = @project.runs.order(started_at: :desc, id: :desc).limit(COMPARE_CHOICES).to_a
    @head = params[:head].present? ? @project.runs.find(params[:head]) : @choices.first
    @base = params[:base].present? ? @project.runs.find(params[:base]) : @head&.previous
    @comparison = RunComparison.new(@base, @head) if @base && @head && @base != @head
  end

  # Insignia SVG para el README de un repositorio: muestra el % de éxito de la última ejecución.
  def badge
    @latest_run = @project.latest_run
    expires_in 1.minute, public: true
    render formats: :svg, content_type: "image/svg+xml"
  end

  def rotate_token
    @project.rotate_api_token!
    redirect_to project_path(@project, anchor: "subir"),
                notice: "Token regenerado. El anterior ya no funciona: actualiza tus scripts y secretos de CI."
  end

  private

  def project_params
    params.require(:project).permit(:name)
  end
end

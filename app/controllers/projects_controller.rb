class ProjectsController < ApplicationController
  before_action :find_project, only: :show

  def index
    @projects = Project.order(:name).to_a
    @latest_runs = Run.where(id: Run.group(:project_id).select("MAX(id)")).index_by(&:project_id)
    @new_project = Project.new
    @created = @projects.find { |p| p.slug == flash[:created_slug] }
  end

  def show
    @latest_run = @project.latest_run
  end

  def create
    @new_project = Project.new(project_params)
    if @new_project.save
      redirect_to projects_path, notice: "Proyecto «#{@new_project.name}» creado.",
                                 flash: { created_slug: @new_project.slug }
    else
      @projects = Project.order(:name).to_a
      @latest_runs = {}
      render :index, status: :unprocessable_content
    end
  end

  private

  def project_params
    params.require(:project).permit(:name)
  end
end

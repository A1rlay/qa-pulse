Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      scope "projects/:slug" do
        get "runs", to: "runs#index", as: :project_runs
        post "runs", to: "runs#create"
        get "flaky", to: "flaky#show", as: :project_flaky
      end
    end
  end

  # Páginas HTML (Paso 3).
  resources :projects, only: %i[index show create], param: :slug do
    resources :runs, only: :show
    get "tests/:test_key", to: "test_histories#show", as: :test_history,
                           constraints: { test_key: /\h{64}/ }
  end
  root "projects#index"

  get "up" => "rails/health#show", as: :rails_health_check
end

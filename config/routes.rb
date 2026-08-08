Rails.application.routes.draw do
  root "dashboard#index"

  # Authentication
  get "login", to: "sessions#new", as: :login
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout

  get "signup", to: "registrations#new", as: :signup
  post "signup", to: "registrations#create"

  # SLA & Analytics Reports
  resources :reports, only: [:index] do
    collection do
      post :send_test_email
    end
  end

  resources :services do
    member do
      post :check_now
    end
  end

  resources :incidents do
    resources :incident_updates, only: [:create]
  end

  resources :maintenance_windows

  # Public Status Pages
  get "status", to: "status_page#show", as: :public_status
  get "status/:org_slug", to: "status_page#show", as: :org_public_status

  # Health check route
  get "up" => "rails/health#show", as: :rails_health_check
end

Rails.application.routes.draw do
  # The landing page is the public face; signed-in operators are redirected
  # straight to the dashboard by MarketingController.
  root "marketing#index"
  get "dashboard", to: "dashboard#index", as: :dashboard

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
      post :pause
      post :resume
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

  # PWA manifest and service worker, rendered from app/views/pwa/. These views
  # shipped with the app but were never routed, so the manifest was dead code.
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end

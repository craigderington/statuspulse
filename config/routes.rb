Rails.application.routes.draw do
  # The landing page is the public face; signed-in operators are redirected
  # straight to the dashboard by MarketingController.
  root "marketing#index"
  get "uptime-monitoring-for-agencies", to: "marketing#agencies", as: :uptime_monitoring_for_agencies
  get "multi-tenant-uptime-monitoring", to: "marketing#multi_tenant", as: :multi_tenant_uptime_monitoring
  get "client-uptime-reports", to: "marketing#reports", as: :client_uptime_reports
  get "pricing", to: "marketing#pricing", as: :pricing
  get "about", to: "marketing#about", as: :about
  get "contact", to: "marketing#contact", as: :contact
  get "privacy", to: "marketing#privacy", as: :privacy
  get "terms", to: "marketing#terms", as: :terms
  get "dashboard", to: "dashboard#index", as: :dashboard

  # Authentication
  get "login", to: "sessions#new", as: :login
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout

  get "signup", to: "registrations#new", as: :signup
  post "signup", to: "registrations#create"

  # Two-factor authentication. The challenge and the enrolment flow are both
  # reachable while only half-authenticated, so they sit outside require_login.
  get  "two-factor", to: "two_factor#new", as: :two_factor
  post "two-factor", to: "two_factor#create"

  get  "two-factor/setup", to: "two_factor_enrolments#new", as: :two_factor_setup
  post "two-factor/setup", to: "two_factor_enrolments#create"
  get  "two-factor/recovery-codes", to: "two_factor_enrolments#recovery_codes", as: :two_factor_recovery_codes
  post "two-factor/recovery-codes", to: "two_factor_enrolments#confirm_recovery_codes", as: :confirm_two_factor_recovery_codes

  # SLA & Analytics Reports
  resources :reports, only: [ :index ] do
    collection do
      post :send_test_email
    end
  end

  # Singular: you edit your own workspace, so there is no id in the URL.
  resource :organization, only: [ :edit, :update ]

  # Alert and email settings for the workspace. Admin-only, like workspace
  # settings: turning alerts off or repointing the webhook affects everyone.
  get   "alerts", to: "alert_settings#edit", as: :alert_settings
  patch "alerts", to: "alert_settings#update"
  post  "alerts/test", to: "alert_settings#test_webhook", as: :test_alert_webhook

  # Personal account security, available to every signed-in user — unlike
  # workspace settings, which are admin-only.
  get  "security", to: "security#show", as: :security
  post "security/recovery-codes", to: "security#regenerate_recovery_codes", as: :regenerate_recovery_codes

  resources :services do
    member do
      post :check_now
      post :pause
      post :resume
    end
  end

  resources :incidents do
    resources :incident_updates, only: [ :create ]
  end

  resources :maintenance_windows

  # Public Status Pages
  get "status", to: "status_page#show", as: :public_status
  get "status/:org_slug", to: "status_page#show", as: :org_public_status

  # Health check route
  get "up" => "rails/health#show", as: :rails_health_check

  # Rendered rather than static so opted-in client status pages are listed as
  # soon as they exist.
  get "sitemap", to: "sitemaps#show", as: :sitemap, defaults: { format: "xml" }

  # PWA manifest and service worker, rendered from app/views/pwa/. These views
  # shipped with the app but were never routed, so the manifest was dead code.
  get "manifest" => "pwa#manifest", as: :pwa_manifest
  get "service-worker" => "pwa#service_worker", as: :pwa_service_worker
end

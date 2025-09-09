Rails.application.routes.draw do
  root "pages#home"
  post "/upload", to: "pages#upload", as: "upload_file"
  get "/process", to: "pages#process_file"
  post "/bulk_validate", to: "emails#bulk_validate"
  resources :emails, only: [ :create, :index ]
end

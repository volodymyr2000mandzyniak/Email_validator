# config/routes.rb
Rails.application.routes.draw do
  root "pages#home"

  post "/upload",  to: "pages#upload",  as: :upload_file
  get  "/process", to: "pages#process_file", as: :process

  resources :emails, only: [] do
    collection do
      post :bulk_validate    # => bulk_validate_emails_path
      get  :progress         # => progress_emails_path
    end
  end
end

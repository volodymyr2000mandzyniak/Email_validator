Rails.application.routes.draw do
  root "pages#home"

  post "/upload",  to: "pages#upload",  as: :upload_file
  get  "/process", to: "pages#process_file", as: :process

  post "/emails/bulk_validate", to: "emails#bulk_validate", as: :bulk_validate_emails
  get  "/emails/progress",      to: "emails#progress",      as: :progress_emails
  get  "/emails/chunk",         to: "emails#chunk",         as: :chunk_emails
  get  "/emails/download",      to: "emails#download",      as: :download_emails
end

class UploadSession < ApplicationRecord
  validates :key, :filename, :path, presence: true
end

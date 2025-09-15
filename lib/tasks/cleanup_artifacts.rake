# lib/tasks/cleanup.rake
namespace :uploads do
  desc "Delete UploadSession records and files older than 24 hours"
  task cleanup: :environment do
    threshold = 24.hours.ago
    UploadSession.where("created_at < ?", threshold).find_each do |us|
      begin
        FileUtils.rm_rf(File.dirname(us.path)) if us.path.present? && File.exist?(us.path)
      rescue => e
        Rails.logger.warn("[cleanup] failed to delete #{us.path}: #{e.message}")
      end
      us.destroy
    end
    puts "Cleanup done"
  end
end

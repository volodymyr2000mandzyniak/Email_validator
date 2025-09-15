class CreateUploadSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :upload_sessions do |t|
      t.string :key
      t.string :filename
      t.string :content_type
      t.bigint :byte_size
      t.string :path

      t.timestamps
    end
    add_index :upload_sessions, :key
  end
end

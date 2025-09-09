class CreateUploadedFiles < ActiveRecord::Migration[8.0]
  def change
    create_table :uploaded_files do |t|
      t.string :name
      t.text :file_data
      t.string :file_type

      t.timestamps
    end
  end
end

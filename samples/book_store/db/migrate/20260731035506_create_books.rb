class CreateBooks < ActiveRecord::Migration[8.1]
  def change
    create_table :books do |t|
      t.string :author
      t.string :name
      t.text :description

      t.timestamps
    end
  end
end

class CreateComments < ActiveRecord::Migration[8.1]
  def change
    create_table :comments do |t|
      t.references :books, null: false, foreign_key: true
      t.string :title
      t.string :text

      t.timestamps
    end
  end
end

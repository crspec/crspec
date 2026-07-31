class Comment < ApplicationRecord
  belongs_to :book, foreign_key: "books_id"

  validates :title, presence: true
  validates :text, presence: true
end

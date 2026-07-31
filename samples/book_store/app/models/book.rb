class Book < ApplicationRecord
  has_many :comments, foreign_key: "books_id", dependent: :destroy

  validates :name, presence: true
  validates :author, presence: true

  def summary
    "#{name} by #{author}"
  end
end

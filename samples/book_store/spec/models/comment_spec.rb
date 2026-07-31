# frozen_string_literal: true

require_relative "../rails_helper"

Crspec.describe Comment, type: :model do
  let(:book) { Book.new(name: "Clean Code", author: "Robert C. Martin") }
  let(:comment_attributes) { { book: book, title: "Great Read!", text: "Highly recommended for all developers." } }
  subject(:comment) { Comment.new(comment_attributes) }

  it "is valid with a title, text, and book association" do
    expect(comment.valid?).to be(true)
  end

  context "when title is missing" do
    let(:comment_attributes) { { book: book, title: nil, text: "Some feedback" } }

    it "is invalid without a title" do
      expect(comment.valid?).to be(false)
      expect(comment.errors[:title]).to include("can't be blank")
    end
  end
end

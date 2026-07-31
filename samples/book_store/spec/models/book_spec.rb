# frozen_string_literal: true

require_relative "../rails_helper"
require "securerandom"

Crspec.describe Book, type: :model do
  let(:valid_attributes) { { name: "The Pragmatic Programmer #{SecureRandom.hex(4)}", author: "Andy Hunt", description: "Your journey to mastery" } }
  subject(:book) { Book.new(valid_attributes) }

  it "is valid with valid attributes" do
    expect(book.valid?).to be(true)
  end

  it "returns a formatted summary" do
    expect(book.summary).to include("by Andy Hunt")
  end

  it "changes book count when saved" do
    unique_name = "Unique Book #{SecureRandom.hex(4)}"
    expect {
      Book.create!(name: unique_name, author: "Andy Hunt", description: "Mastery")
    }.to change { Book.where(name: unique_name).count }.by(1)
  end

  context "when name is missing" do
    let(:valid_attributes) { { name: nil, author: "Andy Hunt" } }

    it "is invalid" do
      expect(book.valid?).to be(false)
      expect(book.errors[:name]).to include("can't be blank")
    end
  end

  context "when author is missing" do
    let(:valid_attributes) { { name: "Design Patterns", author: nil } }

    it "is invalid" do
      expect(book.valid?).to be(false)
      expect(book.errors[:author]).to include("can't be blank")
    end
  end
end

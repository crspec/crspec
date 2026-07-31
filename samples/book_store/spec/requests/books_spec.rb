# frozen_string_literal: true

require_relative "../rails_helper"

Crspec.describe "Books API", type: :request do
  it "lists books via GET" do
    Book.create!(name: "Design Patterns", author: "Gang of Four", description: "Reusable Object-Oriented Software")

    get "/books"

    expect(response.status).to eq(200)
    expect(json_response).not_to be_nil
  end

  it "creates a new book via POST" do
    post "/books", params: { name: "Refactoring", author: "Martin Fowler", description: "Improving the Design of Existing Code" }

    expect([ 200, 201 ]).to include(response.status)
    expect(json_response[:name]).to eq("Refactoring")
  end
end

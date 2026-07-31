# frozen_string_literal: true

require_relative "../rails_helper"
require "securerandom"

Crspec.describe "Users API", type: :request do
  it "creates a user via POST" do
    email = "bob_#{SecureRandom.hex(4)}@example.com"
    post "/users", params: { name: "Bob Martin", email: email }

    expect([ 200, 201 ]).to include(response.status)
    expect(json_response[:email]).to eq(email)
  end
end

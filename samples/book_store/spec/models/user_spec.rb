# frozen_string_literal: true

require_relative "../rails_helper"

Crspec.describe User, type: :model do
  let(:user_attributes) { { name: "Alice Smith", email: "alice@example.com" } }
  subject(:user) { User.new(user_attributes) }

  it "validates primary user attributes" do
    expect(user.valid?).to be(true)
  end

  context "when email is missing" do
    let(:user_attributes) { { name: "Alice Smith", email: nil } }

    it "flags validation error on email" do
      expect(user.valid?).to be(false)
      expect(user.errors[:email]).to include("can't be blank")
    end
  end

  context "when name is missing" do
    let(:user_attributes) { { name: nil, email: "alice@example.com" } }

    it "flags validation error on name" do
      expect(user.valid?).to be(false)
      expect(user.errors[:name]).to include("can't be blank")
    end
  end
end

# frozen_string_literal: true

require "crspec"
require "active_model"

class User
  include ActiveModel::Model

  attr_accessor :name, :email

  validates :name, presence: true
  validates :email, presence: true
end

Crspec.describe User, type: :model do
  let(:valid_attributes) { { name: "Jane Doe", email: "jane@example.com" } }
  subject(:user) { User.new(valid_attributes) }

  it "validates primary attributes" do
    expect(user.valid?).to be(true)
  end

  context "when email is omitted" do
    let(:valid_attributes) { { name: "Jane Doe", email: nil } }

    it "flags validation errors" do
      expect(user.valid?).to be(false)
      expect(user.errors[:email]).to include("can't be blank")
    end
  end
end

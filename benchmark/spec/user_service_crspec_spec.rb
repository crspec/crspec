# frozen_string_literal: true

require_relative "../target_service"

Crspec.describe UserService do
  100.times do |i|
    let(:"user_#{i}") { UserService.process_user(i, "User #{i}", "user#{i}@example.com") }

    it "processes user #{i}" do
      u = send(:"user_#{i}")
      expect(u[:valid]).to be(true)
      expect(u[:token]).not_to be_nil
    end
  end
end

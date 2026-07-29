# frozen_string_literal: true

require "minitest"
require_relative "../target_service"

Minitest.seed ||= srand

class UserServiceTest < Minitest::Test
  parallelize_me! if respond_to?(:parallelize_me!)

  100.times do |i|
    define_method(:"test_user_#{i}") do
      u = UserService.process_user(i, "User #{i}", "user#{i}@example.com")
      assert u[:valid]
      refute_nil u[:token]
    end
  end
end

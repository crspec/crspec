# frozen_string_literal: true

require "test_helper"

class ExecutionContextTest < Minitest::Test
  def test_fiber_storage_isolation_and_inheritance
    parent_ctx = nil
    sub_fiber_ctx = nil

    Crspec::ExecutionContext.isolate("ex-1", { type: :model }) do |ctx|
      parent_ctx = ctx
      assert_equal "ex-1", Crspec::ExecutionContext.current.example_id

      # Sub-fiber created inside example inherits Fiber storage
      Fiber.new do
        sub_fiber_ctx = Crspec::ExecutionContext.current
      end.resume
    end

    assert_equal parent_ctx.example_id, sub_fiber_ctx.example_id
  end

  def test_per_fiber_lazy_memoization
    Crspec::ExecutionContext.isolate("ex-2") do
      ctx = Crspec::ExecutionContext.current
      count = 0
      val1 = ctx.fetch_memoized(:user) do
        count += 1
        "Jane"
      end
      val2 = ctx.fetch_memoized(:user) do
        count += 1
        "Jane"
      end

      assert_equal "Jane", val1
      assert_equal "Jane", val2
      assert_equal 1, count
    end
  end

  def test_thread_safety_memoization
    Crspec::ExecutionContext.isolate("ex-3") do
      ctx = Crspec::ExecutionContext.current
      counter = 0
      threads = Array.new(10) do
        Thread.new do
          ctx.fetch_memoized(:shared_calc) do
            sleep 0.01
            counter += 1
            42
          end
        end
      end

      results = threads.map(&:value)
      assert_equal Array.new(10, 42), results
      assert_equal 1, counter
    end
  end
end

# frozen_string_literal: true

require "test_helper"

class RunnerTest < Minitest::Test
  def setup
    Crspec.reset!
  end

  def test_concurrent_runner_execution
    group = Crspec.describe "User Model" do
      let(:name) { "Alice" }

      it "validates name" do
        expect(name).to eq("Alice")
      end

      it "calculates async property" do
        expect(1 + 1).to eq(2)
      end
    end

    runner = Crspec::Runner.new(concurrency: 2)
    runner.run([group])

    assert runner.success?
    assert_equal 2, runner.passed_examples.size
    assert_equal 0, runner.failed_examples.size
  end

  def test_failing_example_recorded
    group = Crspec.describe "Failing Suite" do
      it "fails expectation" do
        expect(1).to eq(2)
      end
    end

    runner = Crspec::Runner.new(concurrency: 1)
    runner.run([group])

    refute runner.success?
    assert_equal 1, runner.failed_examples.size
    assert_equal "Expected 2, got 1", runner.failed_examples.first.error.message
  end
end

# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class RailsTest < Minitest::Test
  def setup
    Crspec::Rails::Parallel.reset!
    Crspec.reset!
  end

  def teardown
    Crspec::Rails::Parallel.reset!
  end

  def test_database_isolation_wrapper
    mock_example = Minitest::Mock.new
    mock_example.expect(:execute!, true)

    Crspec::Rails::DatabaseIsolation.wrap_example(mock_example)
    assert mock_example.verify
  end

  def test_system_server_start
    Crspec::Rails::SystemServer.reset!
    refute Crspec::Rails::SystemServer.running?

    Crspec::Rails::SystemServer.start_concurrent_server!(nil, 9887)
    assert Crspec::Rails::SystemServer.running?
  end

  def test_rails_parallel_test_setup_and_teardown_hooks
    setup_called = []
    teardown_called = []

    Crspec::Rails::Parallel.parallelize(workers: 2) do
      parallelize_setup do |worker_num|
        setup_called << worker_num
      end

      parallelize_teardown do |worker_num|
        teardown_called << worker_num
      end
    end

    assert Crspec::Rails::Parallel.enabled?
    assert_equal 2, Crspec::Rails::Parallel.worker_count

    group = Crspec.describe "Parallel Test Group" do
      it "runs example" do
        expect(1).to eq(1)
      end
    end

    runner = Crspec::Runner.new(concurrency: 2)
    runner.run([group])

    assert runner.success?
    assert_equal [1, 2], setup_called.sort
    assert_equal [1, 2], teardown_called.sort
  end
end

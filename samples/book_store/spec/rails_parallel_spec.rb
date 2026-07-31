# frozen_string_literal: true

require_relative "rails_helper"

Crspec.describe "Rails Parallel Worker Configuration" do
  it "configures parallel worker environment variables and hooks" do
    setup_called = false
    teardown_called = false

    Crspec::Rails::Parallel.parallelize(workers: 2) do
      parallelize_setup { |_w| setup_called = true }
      parallelize_teardown { |_w| teardown_called = true }
    end

    expect(Crspec::Rails::Parallel.worker_count).to eq(2)

    Crspec::Rails::Parallel.setup_worker(1)
    Crspec::Rails::Parallel.teardown_worker(1)

    expect(setup_called).to be(true)
    expect(teardown_called).to be(true)
  end
end

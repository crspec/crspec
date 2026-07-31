# frozen_string_literal: true

require "etc"
require_relative "assets_shim"
require_relative "warden_shim"

module Crspec
  module Rails
    module Parallel
      WORKER_NUMBER_KEY = :crspec_worker_number

      class << self
        attr_accessor :worker_count, :setup_blocks, :teardown_blocks, :enabled

        def parallelize(workers: :number_of_processors, &block)
          # For Rails test environments it is often safer to run without
          # process-level parallelism unless the application explicitly opts
          # in. This avoids issues with shared transactional fixtures and
          # global state.
          if defined?(::Rails) && ::Rails.respond_to?(:env) && ::Rails.env.test?
            workers = 1 if workers == :number_of_processors
          end
          count = case workers
                  when :number_of_processors
                    Etc.nprocessors
                  when Integer
                    workers
                  else
                    Etc.nprocessors
                  end
          @worker_count = count
          @enabled = true
          @setup_blocks ||= []
          @teardown_blocks ||= []

          return unless block

          instance_eval(&block)
        end

        def enabled?
          !!@enabled
        end

        def parallelize_setup(&block)
          @setup_blocks ||= []
          @setup_blocks << block
        end

        def parallelize_teardown(&block)
          @teardown_blocks ||= []
          @teardown_blocks << block
        end

        # Worker identity lives in Fiber Storage (inherited by fibers
        # spawned within the worker), never in ENV: mutating
        # ENV["TEST_ENV_NUMBER"] from worker threads is a process-wide
        # race. Per-worker databases move to the process tier
        # (--processes), where the ENV convention is safe to set once
        # per child process before any threads start.
        def setup_worker(worker_number)
          Fiber[WORKER_NUMBER_KEY] = worker_number
          @setup_blocks&.each { |b| b.call(worker_number) }
        end

        def current_worker_number
          Fiber[WORKER_NUMBER_KEY]
        end

        def test_env_number(worker_number = current_worker_number)
          return "" if worker_number.nil? || worker_number == 1

          worker_number.to_s
        end

        def teardown_worker(worker_number)
          @teardown_blocks&.each { |b| b.call(worker_number) }
          Fiber[WORKER_NUMBER_KEY] = nil

          return unless defined?(ActiveRecord::Base) && ActiveRecord::Base.respond_to?(:connection_handler)

          begin
            ActiveRecord::Base.connection_handler.clear_active_connections!
          rescue StandardError
            nil
          end
        end

        def reset!
          @enabled = false
          @worker_count = nil
          @setup_blocks = []
          @teardown_blocks = []
        end
      end
    end
  end
end

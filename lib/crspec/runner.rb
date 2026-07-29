# frozen_string_literal: true

require "etc"
require_relative "execution_context"
require_relative "formatters/progress_formatter"

module Crspec
  class Runner
    attr_reader :concurrency, :passed_examples, :failed_examples, :total_duration, :formatter

    def initialize(concurrency: Etc.nprocessors, formatter: nil)
      @concurrency = concurrency
      @formatter = formatter || Formatters::ProgressFormatter.new
      @queue = Thread::Queue.new
      @passed_examples = []
      @failed_examples = []
      @mutex = Mutex.new
      @total_duration = 0
    end

    def run(example_groups)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @formatter.start
      example_groups.each { |group| enqueue_examples(group) }

      workers = Array.new(@concurrency) do |worker_idx|
        Thread.new do
          worker_number = worker_idx + 1
          Rails::Parallel.setup_worker(worker_number) if defined?(Rails::Parallel) && Rails::Parallel.enabled?

          Fiber.set_scheduler(Async::Scheduler.new) if defined?(Async::Scheduler)
          until @queue.empty?
            example = begin
              @queue.pop(true)
            rescue StandardError
              nil
            end
            break unless example

            execute_example(example)
          end
        ensure
          Rails::Parallel.teardown_worker(worker_number) if defined?(Rails::Parallel) && Rails::Parallel.enabled?
        end
      end

      workers.each(&:join)
      @total_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      @formatter.finish
      self
    end

    def success?
      @failed_examples.empty?
    end

    private

    def enqueue_examples(group)
      group.examples.each { |example| @queue.push(example) }
      group.children.each { |child| enqueue_examples(child) }
    end

    def execute_example(example)
      ExecutionContext.isolate(example.id, example.metadata) do |_context|
        example.execute!
      ensure
        if defined?(Mock::Space)
          begin
            Mock::Space.verify_and_reset!
          rescue StandardError => e
            if example.status == :passed
              example.instance_variable_set(:@status, :failed)
              example.instance_variable_set(:@error, e)
            end
          end
        end

        record_result(example)
      end
    end

    def record_result(example)
      @mutex.synchronize do
        if example.status == :passed
          @passed_examples << example
          @formatter.example_passed(example)
        elsif example.status == :pending
          @formatter.example_pending(example)
        else
          @failed_examples << example
          @formatter.example_failed(example)
        end
      end
    end
  end
end

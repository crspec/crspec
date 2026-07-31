# frozen_string_literal: true

require "etc"
begin
  require "async"
  require "async/semaphore"
rescue LoadError
  # Fiber tier unavailable; threads-only execution.
end
require_relative "execution_context"
require_relative "formatters/progress_formatter"
require_relative "status_persistence"

module Crspec
  class Runner
    attr_reader :concurrency, :fibers, :passed_examples, :failed_examples, :pending_examples, :total_duration, :formatter, :seed

    def initialize(concurrency: Etc.nprocessors, fibers: 1, formatter: nil, fail_fast: false,
                   seed: nil, only_failures: false, persistence_path: nil,
                   tags: nil, locations: nil)
      @concurrency = concurrency
      @fibers = fibers && fibers > 1 && defined?(Async) ? fibers : 1
      @formatter = formatter || Formatters::ProgressFormatter.new
      @queue = Thread::Queue.new
      @passed_examples = []
      @failed_examples = []
      @pending_examples = []
      @total_duration = 0
      @fail_fast = fail_fast == true ? 1 : fail_fast
      @failure_count = 0
      @failure_mutex = Mutex.new
      @seed = seed
      @only_failures = only_failures
      @tags = tags
      @locations = locations
      @persistence = StatusPersistence.new(
        persistence_path || Crspec.configuration.example_status_persistence_file_path
      )
    end

    def run(example_groups)
      Rails::AssetsShim.install! if defined?(Rails::AssetsShim)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @formatter.start
      example_groups.each(&:finalize!)

      examples = []
      example_groups.each { |group| collect_examples(group, examples) }
      examples = filter_examples(examples)
      previous_statuses = @persistence.load
      examples = order_examples(examples, previous_statuses)
      examples.each { |example| @queue.push(example) }
      @queue.close

      workers = Array.new(@concurrency) do |worker_idx|
        Thread.new do
          worker_number = worker_idx + 1
          results = { passed: [], failed: [], pending: [] }
          Thread.current[:crspec_results] = results
          Rails::Parallel.setup_worker(worker_number) if defined?(Rails::Parallel) && Rails::Parallel.enabled?

          if @fibers > 1
            run_worker_fibers(results)
          else
            while (example = @queue.pop)
              execute_example(example, results)
            end
          end
        ensure
          Rails::DatabaseIsolation.finish_worker if defined?(Rails::DatabaseIsolation)
          Rails::Parallel.teardown_worker(worker_number) if defined?(Rails::Parallel) && Rails::Parallel.enabled?
        end
      end

      workers.each do |worker|
        worker.join
        results = worker[:crspec_results]
        next unless results

        @passed_examples.concat(results[:passed])
        @failed_examples.concat(results[:failed])
        @pending_examples.concat(results[:pending])
      end
      @total_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      Mock::Interceptor.cleanup! if defined?(Mock::Interceptor)
      @persistence.save(@passed_examples + @failed_examples)
      @formatter.finish
      self
    end

    def success?
      @failed_examples.empty?
    end

    private

    # Each worker thread runs up to @fibers concurrent example-fibers via
    # the Async reactor. IO-bound examples overlap within a thread. Fiber
    # Storage isolation (ExecutionContext, Mock::Space, DB leases) makes
    # this safe: each example fiber gets its own context, mock space and
    # leased DB connection.
    def run_worker_fibers(results)
      Sync do |top|
        semaphore = Async::Semaphore.new(@fibers, parent: top)
        while (example = @queue.pop)
          semaphore.async do
            execute_example(example, results)
          ensure
            Rails::DatabaseIsolation.finish_worker if defined?(Rails::DatabaseIsolation)
          end
        end
      end
    end

    def collect_examples(group, acc)
      acc.concat(group.examples)
      group.children.each { |child| collect_examples(child, acc) }
    end

    # Focus (fit/fdescribe/:focus) narrows to focused examples when any
    # exist; --tag filters on metadata; line-number filters (spec.rb:42)
    # select the example whose definition is closest above the line.
    def filter_examples(examples)
      examples = examples.select(&:focused?) if examples.any?(&:focused?)

      if @tags && !@tags.empty?
        examples = examples.select do |ex|
          meta = ex.example_group.ancestor_metadata.merge(ex.metadata || {})
          @tags.all? do |key, value|
            value == true ? !!meta[key] : meta[key] == value
          end
        end
      end

      if @locations && !@locations.empty?
        examples = examples.select do |ex|
          @locations.any? do |file, line|
            next false unless ex.file_path && File.expand_path(ex.file_path) == File.expand_path(file)
            next true if line.nil?

            candidates = examples.select { |e| e.file_path && File.expand_path(e.file_path) == File.expand_path(file) }
            best = candidates.select { |e| e.line_number && e.line_number <= line }.max_by(&:line_number)
            best ? ex.equal?(best) : false
          end
        end
      end

      examples
    end

    # Slowest-first (using persisted timings) shrinks the critical path of
    # the parallel run; unknown examples go first (assumed potentially slow).
    # --seed applies random ordering before the timing sort is skipped.
    def order_examples(examples, previous_statuses)
      if @only_failures
        examples = examples.select do |ex|
          entry = previous_statuses[ex.persistence_key]
          entry.nil? || entry["status"] == "failed"
        end
      end

      if @seed
        rng = Random.new(@seed)
        examples.shuffle(random: rng)
      elsif previous_statuses.empty?
        examples
      else
        examples.sort_by do |ex|
          entry = previous_statuses[ex.persistence_key]
          -(entry ? entry["run_time"].to_f : Float::INFINITY)
        end
      end
    end

    def execute_example(example, results)
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

        record_result(example, results)
      end
    end

    def record_result(example, results)
      if example.status == :passed
        results[:passed] << example
        @formatter.example_passed(example)
      elsif example.status == :pending
        results[:pending] << example
        @formatter.example_pending(example)
      else
        results[:failed] << example
        @formatter.example_failed(example)
        if @fail_fast
          failures = @failure_mutex.synchronize { @failure_count += 1 }
          @queue.clear if failures >= @fail_fast
        end
      end
    end
  end
end

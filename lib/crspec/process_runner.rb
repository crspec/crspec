# frozen_string_literal: true

require "etc"
require_relative "status_persistence"

module Crspec
  # Process tier for true multi-core execution (--processes P). The parent
  # loads specs once (copy-on-write memory), forks P children, and shards
  # examples across them using persisted timings (bin-packing,
  # slowest-first; round-robin on first run). Each child runs the existing
  # N-thread x M-fiber Runner on its shard and streams marshalled result
  # structs back over a pipe (example blocks cannot cross process
  # boundaries). Fail-fast propagates via SIGTERM.
  class ProcessRunner
    Result = Struct.new(:persistence_key, :description, :status, :error_class,
                        :error_message, :error_backtrace, :execution_time)

    attr_reader :passed_examples, :failed_examples, :pending_examples, :total_duration

    # Forking is only meaningful (and only available) on runtimes with a
    # GVL, i.e. CRuby. On JRuby/TruffleRuby threads already use all cores,
    # so `-c N` is the multi-core tier there.
    def self.fork_supported?
      Process.respond_to?(:fork) && !Process.method(:fork).nil? &&
        RUBY_ENGINE == "ruby"
    end

    def initialize(processes:, concurrency: Etc.nprocessors, fibers: 1, formatter: nil,
                   fail_fast: false, seed: nil, only_failures: false, persistence_path: nil)
      unless self.class.fork_supported?
        raise Crspec::Error, <<~MSG
          --processes requires fork, which #{RUBY_ENGINE} does not support.
          On #{RUBY_ENGINE} threads are not limited by a GVL, so worker
          threads already use all cores: use -c/--concurrency instead
          (e.g. `crspec -c #{Etc.nprocessors}`).
        MSG
      end

      @processes = processes == :auto ? physical_core_count : processes
      @concurrency = concurrency
      @fibers = fibers
      @formatter = formatter || Formatters::ProgressFormatter.new
      @fail_fast = fail_fast == true ? 1 : fail_fast
      @seed = seed
      @only_failures = only_failures
      @persistence_path = persistence_path
      @persistence = StatusPersistence.new(persistence_path)
      @passed_examples = []
      @failed_examples = []
      @pending_examples = []
      @total_duration = 0
    end

    def run(example_groups)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @formatter.start

      example_groups.each(&:finalize!)
      examples = []
      example_groups.each { |group| collect_examples(group, examples) }

      previous = @persistence.load
      if @only_failures
        examples = examples.select do |ex|
          entry = previous[ex.persistence_key]
          entry.nil? || entry["status"] == "failed"
        end
      end

      shards = shard_examples(examples, previous)

      Process.warmup if Process.respond_to?(:warmup)

      children = shards.each_with_index.filter_map do |shard, index|
        next if shard.empty?

        spawn_child(shard, index + 1, example_groups)
      end

      failure_total = 0
      aborted = false
      readers = children.to_h { |c| [c[:reader], c] }

      until readers.empty?
        ready, = IO.select(readers.keys)
        ready.each do |io|
          result = read_result(io)
          if result.nil?
            readers.delete(io)
            io.close
            next
          end

          record(result)
          next unless result.status == "failed" && @fail_fast

          failure_total += 1
          next if aborted || failure_total < @fail_fast

          aborted = true
          children.each do |c|
            Process.kill("TERM", c[:pid])
          rescue Errno::ESRCH
            nil
          end
        end
      end

      children.each do |c|
        Process.wait(c[:pid])
      rescue Errno::ECHILD
        nil
      end

      @total_duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      persist_results(previous)
      @formatter.finish
      self
    end

    def success?
      @failed_examples.empty?
    end

    private

    def collect_examples(group, acc)
      acc.concat(group.examples)
      group.children.each { |child| collect_examples(child, acc) }
    end

    # Longest-processing-time bin packing: sort slowest-first, assign each
    # example to the least-loaded shard. Round-robin when no timings exist.
    def shard_examples(examples, previous)
      shards = Array.new(@processes) { [] }
      if previous.empty?
        examples.each_with_index { |ex, i| shards[i % @processes] << ex }
      else
        loads = Array.new(@processes, 0.0)
        sorted = examples.sort_by do |ex|
          entry = previous[ex.persistence_key]
          -(entry ? entry["run_time"].to_f : Float::INFINITY)
        end
        sorted.each do |ex|
          idx = loads.each_with_index.min_by { |load, _| load }.last
          shards[idx] << ex
          entry = previous[ex.persistence_key]
          loads[idx] += entry ? entry["run_time"].to_f : 0.1
        end
      end
      shards
    end

    def spawn_child(shard, process_number, example_groups)
      reader, writer = IO.pipe
      reader.binmode
      writer.binmode

      pid = fork do
        reader.close
        setup_child_environment(process_number)

        keys = shard.map(&:persistence_key).to_h { |k| [k, true] }
        formatter = ChildFormatter.new(writer)
        runner = Runner.new(concurrency: @concurrency, fibers: @fibers,
                            formatter: formatter, seed: @seed)
        filtered = FilteredGroups.wrap(example_groups, keys)
        runner.run(filtered)
        writer.close
        exit!(runner.success? ? 0 : 1)
      end

      writer.close
      { pid: pid, reader: reader }
    end

    # Per-process databases reuse the Rails parallel-testing convention
    # (database suffixed _N for process N > 1). Set once, pre-thread, where
    # ENV mutation is safe.
    def setup_child_environment(process_number)
      env_num = process_number == 1 ? "" : process_number.to_s
      ENV["TEST_ENV_NUMBER"] = env_num
      ENV["PARALLEL_WORKERS"] = @processes.to_s

      return if process_number == 1
      return unless defined?(ActiveRecord::Base) && ActiveRecord::Base.respond_to?(:connection_db_config)

      # Rails' own parallel-testing helper creates the db_N database and
      # loads the schema, honouring TEST_ENV_NUMBER set above.
      if defined?(ActiveRecord::TestDatabases)
        begin
          ActiveRecord::TestDatabases.create_and_load_schema(process_number, env_name: ::Rails.env)
          return
        rescue StandardError
          nil
        end
      end

      config = begin
        ActiveRecord::Base.connection_db_config
      rescue StandardError
        nil
      end
      return unless config

      db_name = "#{config.database}_#{process_number}"
      begin
        ActiveRecord::Base.establish_connection(config.configuration_hash.merge(database: db_name))
      rescue StandardError
        nil
      end
    end

    def read_result(io)
      header = io.read(4)
      return nil if header.nil? || header.bytesize < 4

      length = header.unpack1("N")
      payload = io.read(length)
      return nil if payload.nil? || payload.bytesize < length

      Marshal.load(payload)
    rescue EOFError, IOError
      nil
    end

    def record(result)
      case result.status
      when "passed"
        @passed_examples << result
        @formatter.example_passed(result)
      when "pending"
        @pending_examples << result
        @formatter.example_pending(result)
      else
        @failed_examples << result
        @formatter.example_failed(result)
      end
    end

    def persist_results(previous)
      (@passed_examples + @failed_examples).each do |result|
        previous[result.persistence_key] = {
          "status" => result.status,
          "run_time" => result.execution_time.to_f.round(6)
        }
      end
      path = @persistence_path
      return unless path

      dir = File.dirname(path)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      File.write(path, JSON.pretty_generate(previous))
    rescue SystemCallError
      nil
    end

    def physical_core_count
      if RUBY_PLATFORM.include?("darwin")
        count = `sysctl -n hw.physicalcpu 2>/dev/null`.to_i
        return count if count.positive?
      elsif File.readable?("/proc/cpuinfo")
        cores = File.read("/proc/cpuinfo").scan(/^core id\s*:\s*(\d+)/).uniq.size
        return cores if cores.positive?
      end
      Etc.nprocessors
    end

    # Streams marshalled Result structs to the parent as examples finish.
    class ChildFormatter
      def initialize(writer)
        @writer = writer
        @mutex = Mutex.new
      end

      def example_passed(example)
        emit(example, "passed")
      end

      def example_failed(example)
        emit(example, "failed")
      end

      def example_pending(example)
        emit(example, "pending")
      end

      def start; end
      def finish; end

      private

      def emit(example, status)
        error = example.respond_to?(:error) ? example.error : nil
        result = Result.new(
          example.persistence_key,
          example.description.to_s,
          status,
          error&.class&.name,
          error&.message,
          error&.backtrace&.first(10),
          example.respond_to?(:execution_time) ? example.execution_time : 0
        )
        payload = Marshal.dump(result)
        @mutex.synchronize do
          @writer.write([payload.bytesize].pack("N"))
          @writer.write(payload)
          @writer.flush
        end
      end
    end

    # Proxy groups that expose only the examples assigned to this shard.
    module FilteredGroups
      def self.wrap(groups, keys)
        groups.map { |g| GroupProxy.new(g, keys) }
      end

      class GroupProxy
        def initialize(group, keys)
          @group = group
          @keys = keys
        end

        def finalize!
          @group.finalize!
          self
        end

        def examples
          @group.examples.select { |ex| @keys[ex.persistence_key] }
        end

        def children
          @group.children.map { |c| GroupProxy.new(c, @keys) }
        end

        def method_missing(name, *args, &block)
          @group.send(name, *args, &block)
        end

        def respond_to_missing?(name, include_private = false)
          @group.respond_to?(name, include_private) || super
        end
      end
    end
  end
end

# frozen_string_literal: true

require "securerandom"
require "monitor"

module Crspec
  class ExecutionContext
    STORAGE_KEY = :crspec_execution_context

    attr_reader :example_id, :metadata, :parent

    def self.current
      Fiber[STORAGE_KEY] ||= new(SecureRandom.uuid)
    end

    def self.isolate(example_id, metadata = {})
      new_context = new(example_id, metadata, Fiber[STORAGE_KEY])
      old_context = Fiber[STORAGE_KEY]
      old_space = Fiber[Mock::Space::STORAGE_KEY]
      Fiber[STORAGE_KEY] = new_context
      Fiber[Mock::Space::STORAGE_KEY] = nil
      begin
        yield new_context
      ensure
        Fiber[STORAGE_KEY] = old_context
        Fiber[Mock::Space::STORAGE_KEY] = old_space
      end
    end

    def initialize(example_id, metadata = {}, parent = nil)
      @example_id = example_id
      @metadata = metadata.freeze
      @parent = parent
      @memoized_values = {}
      @monitor = Monitor.new
    end

    def fetch_memoized(key, &block)
      return @memoized_values[key] if @memoized_values.key?(key)

      @monitor.synchronize do
        return @memoized_values[key] if @memoized_values.key?(key)

        @memoized_values[key] = yield
      end
    end

    def [](key)
      @monitor.synchronize do
        @memoized_values[key]
      end
    end

    def []=(key, value)
      @monitor.synchronize do
        @memoized_values[key] = value
      end
    end

    def reset!
      @monitor.synchronize do
        @memoized_values.clear
      end
    end
  end
end

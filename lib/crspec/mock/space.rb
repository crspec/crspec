# frozen_string_literal: true

require_relative "interceptor"

module Crspec
  module Mock
    class Space
      STORAGE_KEY = :crspec_mock_space

      def self.current
        Fiber[STORAGE_KEY] ||= new
      end

      def self.verify_and_reset!
        space = Fiber[STORAGE_KEY]
        return unless space

        begin
          space.verify!
        ensure
          space.reset!
          Fiber[STORAGE_KEY] = nil
        end
      end

      def initialize
        @doubles = []
        @stubs = Hash.new { |h, k| h[k] = {} }
        @expectations = []
        @calls = Hash.new { |h, k| h[k] = [] }
        @mutex = Mutex.new
      end

      def record_call(target, method_name, args, kwargs)
        @mutex.synchronize do
          @calls[[target.object_id, method_name.to_sym]] << [args, kwargs]
        end
      end

      def calls_for(target, method_name)
        @mutex.synchronize do
          @calls[[target.object_id, method_name.to_sym]].dup
        end
      end

      def register_stub(target, method_name, implementation)
        method_sym = method_name.to_sym
        ensure_interceptor_prepended(target, method_sym)
        @mutex.synchronize do
          @stubs[target.object_id][method_sym] = implementation
        end
      end

      def fetch_stub(target, method_name)
        @mutex.synchronize do
          @stubs[target.object_id][method_name.to_sym]
        end
      end

      def register_expectation(expectation)
        @mutex.synchronize do
          @expectations << expectation
        end
      end

      def register_double(double_obj)
        @mutex.synchronize do
          @doubles << double_obj
        end
      end

      def verify!
        @expectations.each(&:verify_expectations!)
        @doubles.each(&:verify_expectations!)
      end

      def reset!
        @mutex.synchronize do
          @stubs.clear
          @doubles.clear
          @expectations.clear
          @calls.clear
        end
      end

      private

      def ensure_interceptor_prepended(target, method_name)
        klass = target.singleton_class
        klass.prepend(Interceptor) unless klass.include?(Interceptor)
        Interceptor.add_intercept_method(method_name)
      end
    end
  end
end

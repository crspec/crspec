# frozen_string_literal: true

module Crspec
  module Mock
    # RSpec-style argument matchers usable in with(...) and have_received
    # constraints. Each responds to ===(actual).
    module ArgumentMatchers
      class Anything
        def ===(_other) = true
        def ==(other) = true
        def inspect = "anything"
      end

      class HashIncluding
        def initialize(expected)
          @expected = expected
        end

        def ===(actual)
          return false unless actual.is_a?(Hash)

          @expected.all? { |k, v| actual.key?(k) && (v == actual[k] || v === actual[k]) }
        end
        alias == ===

        def inspect = "hash_including(#{@expected.inspect})"
      end

      class HashExcluding
        def initialize(expected)
          @expected = expected
        end

        def ===(actual)
          return false unless actual.is_a?(Hash)

          @expected.none? { |k, v| actual.key?(k) && (v == actual[k] || v === actual[k]) }
        end
        alias == ===

        def inspect = "hash_excluding(#{@expected.inspect})"
      end

      class ArrayIncluding
        def initialize(expected)
          @expected = expected
        end

        def ===(actual)
          return false unless actual.is_a?(Array)

          @expected.all? { |item| actual.any? { |el| item == el || item === el } }
        end
        alias == ===

        def inspect = "array_including(#{@expected.inspect})"
      end

      class InstanceOf
        def initialize(klass)
          @klass = klass
        end

        def ===(actual) = actual.instance_of?(@klass)
        alias == ===

        def inspect = "an_instance_of(#{@klass})"
      end

      class KindOf
        def initialize(klass)
          @klass = klass
        end

        def ===(actual) = actual.is_a?(@klass)
        alias == ===

        def inspect = "kind_of(#{@klass})"
      end

      class Duck
        def initialize(*methods)
          @methods = methods
        end

        def ===(actual) = @methods.all? { |m| actual.respond_to?(m) }
        alias == ===

        def inspect = "duck_type(#{@methods.map(&:inspect).join(", ")})"
      end

      def anything
        Anything.new
      end

      def hash_including(expected = {}, **kwargs)
        HashIncluding.new(expected.merge(kwargs))
      end

      def hash_excluding(expected = {}, **kwargs)
        HashExcluding.new(expected.merge(kwargs))
      end

      def array_including(*items)
        ArrayIncluding.new(items.flatten(1))
      end

      def an_instance_of(klass)
        InstanceOf.new(klass)
      end
      alias instance_of an_instance_of

      def kind_of(klass)
        KindOf.new(klass)
      end
      alias a_kind_of kind_of

      def duck_type(*methods)
        Duck.new(*methods)
      end

      def self.args_match?(expected_args, actual_args, actual_kwargs = nil)
        return true if expected_args.nil?

        # A trailing hash matcher (hash_including etc.) may target the
        # call's keyword arguments.
        if actual_kwargs && !actual_kwargs.empty? &&
           expected_args.size == actual_args.size + 1 &&
           (expected_args.last.is_a?(HashIncluding) || expected_args.last.is_a?(HashExcluding) || expected_args.last.is_a?(Hash))
          positional = expected_args[0...-1]
          return args_match?(positional, actual_args) &&
                 (expected_args.last == actual_kwargs || expected_args.last === actual_kwargs)
        end

        return false unless expected_args.size == actual_args.size

        expected_args.zip(actual_args).all? do |expected, actual|
          expected == actual || expected === actual
        end
      end

      def self.kwargs_match?(expected_kwargs, actual_kwargs)
        return true if expected_kwargs.nil? || expected_kwargs.empty?

        if expected_kwargs.size == 1 && expected_kwargs.values.first.is_a?(HashIncluding)
          return expected_kwargs.values.first === actual_kwargs
        end

        return false unless expected_kwargs.size == actual_kwargs.size

        expected_kwargs.all? do |key, expected|
          actual_kwargs.key?(key) && (expected == actual_kwargs[key] || expected === actual_kwargs[key])
        end
      end
    end
  end
end

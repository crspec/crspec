# frozen_string_literal: true

module Crspec
  module Matchers
    class BaseMatcher
      attr_reader :actual, :expected

      def initialize(expected = nil)
        @expected = expected
      end

      def failure_message
        "Expected #{@actual.inspect} to match #{@expected.inspect}"
      end

      def failure_message_when_negated
        "Expected #{@actual.inspect} not to match #{@expected.inspect}"
      end
    end

    class EqMatcher < BaseMatcher
      def matches?(actual)
        @actual = actual
        @actual == @expected
      end

      def failure_message
        "Expected #{@expected.inspect}, got #{@actual.inspect}"
      end

      def failure_message_when_negated
        "Expected value not to equal #{@expected.inspect}"
      end
    end

    class BeMatcher < BaseMatcher
      def matches?(actual)
        @actual = actual
        if @expected.nil? && !instance_variable_defined?(:@expected)
          true
        elsif @expected.equal?(true) || @expected.equal?(false)
          @actual == @expected
        else
          @actual.equal?(@expected)
        end
      end

      def failure_message
        "Expected #{@expected.inspect} (object_id: #{@expected.object_id}), got #{@actual.inspect} (object_id: #{@actual.object_id})"
      end
    end

    class BeNilMatcher < BaseMatcher
      def matches?(actual)
        @actual = actual
        @actual.nil?
      end

      def failure_message
        "Expected #{@actual.inspect} to be nil"
      end

      def failure_message_when_negated
        "Expected #{@actual.inspect} not to be nil"
      end
    end

    class BeTruthyMatcher < BaseMatcher
      def matches?(actual)
        @actual = actual
        !!@actual
      end

      def failure_message
        "Expected #{@actual.inspect} to be truthy"
      end
    end

    class BeFalsyMatcher < BaseMatcher
      def matches?(actual)
        @actual = actual
        !@actual
      end

      def failure_message
        "Expected #{@actual.inspect} to be falsy"
      end
    end

    class IncludeMatcher < BaseMatcher
      def matches?(actual)
        @actual = actual
        if @expected.is_a?(Array)
          @expected.all? { |e| @actual.include?(e) }
        else
          @actual.include?(@expected)
        end
      end

      def failure_message
        "Expected #{@actual.inspect} to include #{@expected.inspect}"
      end

      def failure_message_when_negated
        "Expected #{@actual.inspect} not to include #{@expected.inspect}"
      end
    end

    class RaiseErrorMatcher < BaseMatcher
      def initialize(expected_exception = StandardError, expected_message = nil)
        super(expected_exception)
        @expected_exception = expected_exception
        @expected_message = expected_message
        @actual_exception = nil
      end

      def matches?(block)
        raise ArgumentError, "raise_error matcher requires a block" unless block.respond_to?(:call)

        begin
          block.call
          false
        rescue Exception => e
          @actual_exception = e
          matches_exception?(e)
        end
      end

      def failure_message
        if @actual_exception
          "Expected #{@expected_exception}#{@expected_message ? " with message #{@expected_message.inspect}" : ""}, but got #{@actual_exception.class}: #{@actual_exception.message.inspect}"
        else
          "Expected #{@expected_exception} to be raised, but nothing was raised"
        end
      end

      def failure_message_when_negated
        "Expected no exception, but #{@actual_exception.class} was raised"
      end

      private

      def matches_exception?(e)
        return false unless e.is_a?(@expected_exception)
        return true unless @expected_message

        if @expected_message.is_a?(Regexp)
          @expected_message.match?(e.message)
        else
          e.message.include?(@expected_message.to_s)
        end
      end
    end

    class RespondToMatcher < BaseMatcher
      def initialize(*methods)
        super(methods)
        @methods = methods
      end

      def matches?(actual)
        @actual = actual
        @methods.all? { |m| @actual.respond_to?(m) }
      end

      def failure_message
        "Expected #{@actual.inspect} to respond to #{@methods.map(&:inspect).join(", ")}"
      end
    end

    class ChangeMatcher < BaseMatcher
      def initialize(receiver = nil, message = nil, &block)
        super()
        @receiver = receiver
        @message = message
        @block = block || -> { receiver.send(message) }
        @expected_by = nil
        @expected_from = nil
        @expected_to = nil
      end

      def by(amount)
        @expected_by = amount
        self
      end

      def from(val)
        @expected_from = val
        self
      end

      def to(val)
        @expected_to = val
        self
      end

      def matches?(proc_to_run)
        @before_val = @block.call
        proc_to_run.call
        @after_val = @block.call

        if @expected_by
          (@after_val - @before_val) == @expected_by
        elsif !@expected_from.nil? && !@expected_to.nil?
          @before_val == @expected_from && @after_val == @expected_to
        elsif !@expected_to.nil?
          @after_val == @expected_to
        else
          @before_val != @after_val
        end
      end

      def failure_message
        if @expected_by
          "Expected result to change by #{@expected_by}, but changed by #{@after_val - @before_val} (from #{@before_val.inspect} to #{@after_val.inspect})"
        else
          "Expected result to change, but remained #{@before_val.inspect}"
        end
      end
    end

    def eq(expected)
      EqMatcher.new(expected)
    end

    def be(expected = nil)
      BeMatcher.new(expected)
    end

    def be_nil
      BeNilMatcher.new
    end

    def be_truthy
      BeTruthyMatcher.new
    end

    def be_falsy
      BeFalsyMatcher.new
    end

    def include(*expected)
      IncludeMatcher.new(expected.size == 1 ? expected.first : expected)
    end

    def raise_error(expected_exception = StandardError, message = nil)
      RaiseErrorMatcher.new(expected_exception, message)
    end

    def respond_to(*methods)
      RespondToMatcher.new(*methods)
    end

    def change(receiver = nil, message = nil, &block)
      ChangeMatcher.new(receiver, message, &block)
    end
  end
end

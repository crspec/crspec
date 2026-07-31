# frozen_string_literal: true

require_relative "space"

module Crspec
  module Mock
    class MockError < StandardError; end

    class Double
      attr_reader :name

      def initialize(name = nil, stubs = {})
        @name = name || "Double"
        Space.current.register_double(self)
        stubs.each do |method_name, return_value|
          Space.current.register_stub(self, method_name, proc { return_value })
        end
      end

      def verify_expectations!
        # Verified via Space
      end

      def inspect
        "#<Double #{@name.inspect}>"
      end
    end

    class StubChain
      attr_reader :target, :method_name

      def initialize(target, method_name)
        @target = target
        @method_name = method_name.to_sym
        @expected_args = nil
        @return_proc = proc {}
        register_default_stub
      end

      def with(*args)
        @expected_args = args
        update_stub
        self
      end

      def and_return(*values)
        if values.size == 1
          val = values.first
          @return_proc = proc { val }
        else
          idx = 0
          @return_proc = proc do
            res = values[idx] || values.last
            idx += 1
            res
          end
        end
        update_stub
        self
      end

      def and_raise(exception = StandardError, message = nil)
        @return_proc = proc do
          err = exception.is_a?(Class) ? exception.new(message) : exception
          raise err
        end
        update_stub
        self
      end

      def and_yield(*yield_args)
        old_proc = @return_proc
        @return_proc = proc do |*args, &block|
          block&.call(*yield_args)
          old_proc.call(*args)
        end
        update_stub
        self
      end

      private

      def register_default_stub
        update_stub
      end

      def update_stub
        target = @target
        method_name = @method_name
        expected_args = @expected_args
        return_proc = @return_proc

        implementation = proc do |*args, **kwargs, &block|
          if expected_args && args != expected_args
            raise MockError, "Expected #{method_name} with #{expected_args.inspect}, got #{args.inspect}"
          end

          return_proc.call(*args, **kwargs, &block)
        end

        Space.current.register_stub(target, method_name, implementation)
      end
    end

    class ExpectationChain < StubChain
      def initialize(target, method_name)
        @call_count = 0
        @expected_count = 1
        @count_constraint = :exact
        super(target, method_name)
        Space.current.register_expectation(self)
      end

      def once
        @expected_count = 1
        @count_constraint = :exact
        self
      end

      def twice
        @expected_count = 2
        @count_constraint = :exact
        self
      end

      def exactly(n)
        @expected_count = n
        @count_constraint = :exact
        self
      end

      def at_least(n)
        @expected_count = n
        @count_constraint = :at_least
        self
      end

      def verify_expectations!
        valid = case @count_constraint
                when :exact then @call_count == @expected_count
                when :at_least then @call_count >= @expected_count
                end

        return if valid

        raise MockError,
              "Expected #{@target.inspect} to receive #{@method_name.inspect} #{@count_constraint} #{@expected_count} times, but received it #{@call_count} times"
      end

      private

      def update_stub
        target = @target
        method_name = @method_name
        expected_args = @expected_args
        return_proc = @return_proc

        implementation = proc do |*args, **kwargs, &block|
          @call_count += 1
          if expected_args && args != expected_args
            raise MockError, "Expected #{method_name} with #{expected_args.inspect}, got #{args.inspect}"
          end

          return_proc.call(*args, **kwargs, &block)
        end

        Space.current.register_stub(target, method_name, implementation)
      end
    end

    class ReceiveMatcher
      attr_reader :method_name

      def initialize(method_name)
        @method_name = method_name.to_sym
        @expected_args = nil
        @return_values = nil
        @raise_exception = nil
        @yield_args = nil
        @expected_count = 1
        @count_constraint = :exact
      end

      def with(*args)
        @expected_args = args
        self
      end

      def and_return(*values)
        @return_values = values
        self
      end

      def and_raise(exception = StandardError, message = nil)
        @raise_exception = exception
        @raise_message = message
        self
      end

      def and_yield(*args)
        @yield_args = args
        self
      end

      def once
        @expected_count = 1
        @count_constraint = :exact
        self
      end

      def twice
        @expected_count = 2
        @count_constraint = :exact
        self
      end

      def exactly(n)
        @expected_count = n
        @count_constraint = :exact
        self
      end

      def at_least(n)
        @expected_count = n
        @count_constraint = :at_least
        self
      end

      def setup_allow(target)
        chain = StubChain.new(target, @method_name)
        apply_chain_options(chain)
        chain
      end

      def setup_expect(target)
        chain = ExpectationChain.new(target, @method_name)
        chain.instance_variable_set(:@expected_count, @expected_count)
        chain.instance_variable_set(:@count_constraint, @count_constraint)
        apply_chain_options(chain)
        chain
      end

      private

      def apply_chain_options(chain)
        chain.with(*@expected_args) if @expected_args
        chain.and_return(*@return_values) if @return_values
        chain.and_raise(@raise_exception, @raise_message) if @raise_exception
        chain.and_yield(*@yield_args) if @yield_args
      end
    end

    class AllowTarget
      def initialize(target)
        @target = target
      end

      def to(matcher)
        if matcher.respond_to?(:setup_allow)
          matcher.setup_allow(@target)
        else
          matcher.call(@target)
        end
      end
    end

    module DSL
      def double(name = nil, stubs = {})
        Double.new(name, stubs)
      end

      def instance_double(target_class, name = nil, stubs = {})
        double_name = if target_class.is_a?(String) || target_class.is_a?(Symbol)
                        target_class.to_s
                      elsif target_class.respond_to?(:name)
                        target_class.name
                      else
                        target_class.to_s
                      end
        Double.new(name || double_name, stubs)
      end

      def allow(target)
        AllowTarget.new(target)
      end

      def receive(method_name)
        ReceiveMatcher.new(method_name)
      end
    end
  end
end

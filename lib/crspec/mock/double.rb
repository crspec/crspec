# frozen_string_literal: true

require_relative "space"
require_relative "argument_matchers"

module Crspec
  module Mock
    class MockError < StandardError; end

    class Double
      attr_reader :name

      def initialize(name = nil, stubs = {})
        @name = name || "Double"
        Space.current.register_double(self)
        stubs.each do |method_name, return_value|
          __crspec_verify_stub!(method_name)
          Space.current.register_stub(self, method_name, proc { return_value })
        end
      end

      def __crspec_verify_stub!(method_name)
        # Plain doubles accept any stub.
      end

      def verify_expectations!
        # Verified via Space
      end

      def inspect
        "#<Double #{@name.inspect}>"
      end
    end

    # A verifying double: only methods that exist on the doubled class's
    # instance interface may be stubbed or expected.
    class InstanceDouble < Double
      def initialize(doubled_class, name = nil, stubs = {})
        @doubled_class = doubled_class.is_a?(Module) ? doubled_class : nil
        @doubled_class_name = doubled_class.is_a?(Module) ? doubled_class.name : doubled_class.to_s
        super(name || @doubled_class_name, stubs)
      end

      def __crspec_verify_stub!(method_name)
        return unless @doubled_class

        method_sym = method_name.to_sym
        return if @doubled_class.method_defined?(method_sym) ||
                  @doubled_class.private_method_defined?(method_sym)

        raise MockError,
              "the #{@doubled_class_name} class does not implement the instance method: #{method_sym}"
      end

      def inspect
        "#<InstanceDouble(#{@doubled_class_name}) #{@name.inspect}>"
      end
    end

    class StubChain
      attr_reader :target, :method_name

      def initialize(target, method_name)
        @target = target
        @method_name = method_name.to_sym
        target.__crspec_verify_stub!(@method_name) if target.respond_to?(:__crspec_verify_stub!)
        @expected_args = nil
        @expected_kwargs = nil
        @return_proc = proc {}
        register_default_stub
      end

      def with(*args, **kwargs)
        @expected_args = args
        @expected_kwargs = kwargs
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

      def and_call_original
        target = @target
        method_name = @method_name
        original = begin
          target.method(method_name)
        rescue NameError
          raise MockError, "#{target.inspect} has no original implementation of #{method_name}"
        end
        # Find the implementation beneath the interceptor.
        original = original.super_method while original && original.owner == Interceptor
        raise MockError, "#{target.inspect} has no original implementation of #{method_name}" unless original

        @return_proc = proc { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
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
        expected_kwargs = @expected_kwargs
        return_proc = @return_proc

        implementation = proc do |*args, **kwargs, &block|
          Space.current.record_call(target, method_name, args, kwargs)
          if expected_args && !expected_args.empty? && !ArgumentMatchers.args_match?(expected_args, args, kwargs)
            raise MockError, "Expected #{method_name} with #{expected_args.inspect}, got #{args.inspect}"
          end

          if expected_kwargs && !expected_kwargs.empty? && !ArgumentMatchers.kwargs_match?(expected_kwargs, kwargs)
            raise MockError, "Expected #{method_name} with #{expected_kwargs.inspect}, got #{kwargs.inspect}"
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
        expected_kwargs = @expected_kwargs
        return_proc = @return_proc

        implementation = proc do |*args, **kwargs, &block|
          @call_count += 1
          Space.current.record_call(target, method_name, args, kwargs)
          if expected_args && !expected_args.empty? && !ArgumentMatchers.args_match?(expected_args, args, kwargs)
            raise MockError, "Expected #{method_name} with #{expected_args.inspect}, got #{args.inspect}"
          end

          if expected_kwargs && !expected_kwargs.empty? && !ArgumentMatchers.kwargs_match?(expected_kwargs, kwargs)
            raise MockError, "Expected #{method_name} with #{expected_kwargs.inspect}, got #{kwargs.inspect}"
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
        @expected_kwargs = nil
        @return_values = nil
        @raise_exception = nil
        @yield_args = nil
        @expected_count = 1
        @count_constraint = :exact
      end

      def with(*args, **kwargs)
        @expected_args = args
        @expected_kwargs = kwargs
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

      def and_call_original
        @call_original = true
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
        if @expected_args || @expected_kwargs
          chain.with(*(@expected_args || []), **(@expected_kwargs || {}))
        end
        chain.and_return(*@return_values) if @return_values
        chain.and_raise(@raise_exception, @raise_message) if @raise_exception
        chain.and_yield(*@yield_args) if @yield_args
        chain.and_call_original if @call_original
      end
    end

    # allow(target).to receive_messages(a: 1, b: 2)
    class ReceiveMessagesMatcher
      def initialize(messages)
        @messages = messages
      end

      def setup_allow(target)
        @messages.map do |method_name, value|
          StubChain.new(target, method_name).and_return(value)
        end
      end

      def setup_expect(target)
        @messages.map do |method_name, value|
          ExpectationChain.new(target, method_name).and_return(value)
        end
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

    # expect(target).to have_received(:method).with(...).once
    class HaveReceivedMatcher
      def initialize(method_name)
        @method_name = method_name.to_sym
        @expected_args = nil
        @expected_kwargs = nil
        @expected_count = nil
        @count_constraint = :at_least_once
      end

      def with(*args, **kwargs)
        @expected_args = args
        @expected_kwargs = kwargs
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

      def times
        self
      end

      def at_least(n)
        @expected_count = n
        @count_constraint = :at_least
        self
      end

      def matches?(target)
        @target = target
        calls = Space.current.calls_for(target, @method_name)
        if @expected_args || @expected_kwargs
          calls = calls.select do |args, kwargs|
            ArgumentMatchers.args_match?(@expected_args, args, kwargs) &&
              ArgumentMatchers.kwargs_match?(@expected_kwargs, kwargs)
          end
        end
        @actual_count = calls.size

        case @count_constraint
        when :exact then @actual_count == @expected_count
        when :at_least then @actual_count >= @expected_count
        else @actual_count.positive?
        end
      end

      def failure_message
        expectation = case @count_constraint
                      when :exact then "exactly #{@expected_count} time(s)"
                      when :at_least then "at least #{@expected_count} time(s)"
                      else "at least once"
                      end
        with_clause = @expected_args ? " with #{@expected_args.inspect}" : ""
        "Expected #{@target.inspect} to have received #{@method_name.inspect}#{with_clause} #{expectation}, " \
          "but received it #{@actual_count} time(s)"
      end

      def failure_message_when_negated
        "Expected #{@target.inspect} not to have received #{@method_name.inspect}, " \
          "but received it #{@actual_count} time(s)"
      end
    end

    # A spy: a double that accepts any message and records calls for
    # have_received verification.
    class Spy < Double
      def method_missing(method_name, *args, **kwargs, &block)
        space = Fiber[Space::STORAGE_KEY]
        if space
          if (stub = space.fetch_stub(self, method_name))
            return stub.call(*args, **kwargs, &block)
          end

          space.record_call(self, method_name, args, kwargs)
        end
        nil
      end

      def respond_to_missing?(_method_name, _include_private = false)
        true
      end

      def inspect
        "#<Spy #{@name.inspect}>"
      end
    end

    module DSL
      include ArgumentMatchers

      def double(name = nil, stubs = {})
        Double.new(name, stubs)
      end

      def instance_double(target_class, name = nil, stubs = {})
        if name.is_a?(Hash) && stubs.empty?
          stubs = name
          name = nil
        end
        resolved = if target_class.is_a?(String) || target_class.is_a?(Symbol)
                     begin
                       Object.const_get(target_class.to_s)
                     rescue NameError
                       target_class.to_s
                     end
                   else
                     target_class
                   end
        InstanceDouble.new(resolved, name, stubs)
      end

      def allow(target)
        AllowTarget.new(target)
      end

      def receive(method_name)
        ReceiveMatcher.new(method_name)
      end

      def receive_messages(messages)
        ReceiveMessagesMatcher.new(messages)
      end

      def spy(name = nil, stubs = {})
        Spy.new(name || "Spy", stubs)
      end

      def have_received(method_name)
        HaveReceivedMatcher.new(method_name)
      end

      def allow_any_instance_of(_klass)
        raise Crspec::MigrationError, <<~MSG
          allow_any_instance_of is not supported by Crspec: it mutates shared
          class hierarchies at runtime, which is unsafe under concurrent
          threads/fibers. Inject a double or stub the specific instance.
          Run `crspec-transpile --analyze` to find all occurrences.
        MSG
      end

      def expect_any_instance_of(_klass)
        raise Crspec::MigrationError, <<~MSG
          expect_any_instance_of is not supported by Crspec: it mutates shared
          class hierarchies at runtime, which is unsafe under concurrent
          threads/fibers. Inject a double or stub the specific instance.
          Run `crspec-transpile --analyze` to find all occurrences.
        MSG
      end
    end
  end
end

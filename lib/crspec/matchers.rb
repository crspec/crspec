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

      def and(other)
        CompoundAndMatcher.new(self, other)
      end

      def or(other)
        CompoundOrMatcher.new(self, other)
      end
    end

    class CompoundAndMatcher
      def initialize(first, second)
        @first = first
        @second = second
      end

      def matches?(actual)
        @first_matched = @first.matches?(actual)
        @second_matched = @second.matches?(actual)
        @first_matched && @second_matched
      end

      def failure_message
        messages = []
        messages << @first.failure_message unless @first_matched
        messages << @second.failure_message unless @second_matched
        messages.join("\n...and:\n")
      end

      def failure_message_when_negated
        "Expected compound matcher not to match"
      end

      def and(other)
        CompoundAndMatcher.new(self, other)
      end

      def or(other)
        CompoundOrMatcher.new(self, other)
      end
    end

    class CompoundOrMatcher < CompoundAndMatcher
      def matches?(actual)
        @first.matches?(actual) || @second.matches?(actual)
      end

      def failure_message
        "#{@first.failure_message}\n...or:\n#{@second.failure_message}"
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

    class BeAKindOfMatcher < BaseMatcher
      def matches?(actual)
        @actual = actual
        @actual.is_a?(@expected)
      end

      def failure_message
        "Expected #{@actual.inspect} to be a kind of #{@expected}"
      end

      def failure_message_when_negated
        "Expected #{@actual.inspect} not to be a kind of #{@expected}"
      end
    end

    class BeAnInstanceOfMatcher < BaseMatcher
      def matches?(actual)
        @actual = actual
        @actual.instance_of?(@expected)
      end

      def failure_message
        "Expected #{@actual.inspect} to be an instance of #{@expected}, but was #{@actual.class}"
      end

      def failure_message_when_negated
        "Expected #{@actual.inspect} not to be an instance of #{@expected}"
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

    class PredicateMatcher < BaseMatcher
      def initialize(predicate, description, *args, **kwargs, &block)
        super(nil)
        @predicate = predicate
        @description = description
        @args = args
        @kwargs = kwargs
        @block = block
      end

      def matches?(actual)
        @actual = actual
        unless @actual.respond_to?(@predicate)
          raise NoMethodError, "undefined method '#{@predicate}' for #{@actual.inspect}"
        end

        !!@actual.public_send(@predicate, *@args, **@kwargs, &@block)
      end

      def failure_message
        "Expected #{@actual.inspect} to #{@description}#{args_description}"
      end

      def failure_message_when_negated
        "Expected #{@actual.inspect} not to #{@description}#{args_description}"
      end

      private

      def args_description
        return "" if @args.empty? && @kwargs.empty?

        parts = @args.map(&:inspect) + @kwargs.map { |k, v| "#{k}: #{v.inspect}" }
        " with #{parts.join(", ")}"
      end
    end

    class HaveHttpStatusMatcher < BaseMatcher
      STATUS_GROUPS = {
        success: 200..299,
        successful: 200..299,
        redirect: 300..399,
        error: 500..599,
        server_error: 500..599,
        client_error: 400..499,
        missing: [404]
      }.freeze

      FALLBACK_CODES = {
        ok: 200, created: 201, accepted: 202, no_content: 204,
        moved_permanently: 301, found: 302, see_other: 303, not_modified: 304,
        bad_request: 400, unauthorized: 401, forbidden: 403, not_found: 404,
        method_not_allowed: 405, not_acceptable: 406, conflict: 409, gone: 410,
        unprocessable_entity: 422, unprocessable_content: 422, too_many_requests: 429,
        internal_server_error: 500, not_implemented: 501, bad_gateway: 502,
        service_unavailable: 503
      }.freeze

      def initialize(expected)
        super(expected)
      end

      def matches?(actual)
        @actual = actual
        @actual_status = actual.respond_to?(:status) ? actual.status : actual
        expected_codes.include?(@actual_status)
      end

      def failure_message
        "Expected response to have HTTP status #{@expected.inspect}, got #{@actual_status.inspect}"
      end

      def failure_message_when_negated
        "Expected response not to have HTTP status #{@expected.inspect}, but it did (#{@actual_status.inspect})"
      end

      private

      def expected_codes
        case @expected
        when Integer then [@expected]
        when Range then @expected
        when Symbol, String
          sym = @expected.to_sym
          group = STATUS_GROUPS[sym]
          return group if group

          if defined?(::Rack::Utils::SYMBOL_TO_STATUS_CODE)
            code = ::Rack::Utils::SYMBOL_TO_STATUS_CODE[sym]
            return [code] if code
          end
          code = FALLBACK_CODES[sym]
          return [code] if code

          raise ArgumentError, "Unknown HTTP status: #{@expected.inspect}"
        else
          raise ArgumentError, "Invalid HTTP status: #{@expected.inspect}"
        end
      end
    end

    class MatchMatcher < BaseMatcher
      def matches?(actual)
        @actual = actual
        case @expected
        when Regexp then @expected.match?(actual.to_s)
        when String then actual.is_a?(Regexp) ? actual.match?(@expected) : actual == @expected
        else values_match?(@expected, actual)
        end
      end

      def failure_message
        "Expected #{@actual.inspect} to match #{@expected.inspect}"
      end

      private

      def values_match?(expected, actual)
        case expected
        when Array
          return false unless actual.is_a?(Array) && actual.size == expected.size

          expected.zip(actual).all? { |e, a| values_match?(e, a) }
        when Hash
          return false unless actual.is_a?(Hash) && actual.size == expected.size

          expected.all? { |k, v| actual.key?(k) && values_match?(v, actual[k]) }
        when Regexp
          expected.match?(actual.to_s)
        else
          expected === actual || expected == actual
        end
      end
    end

    class MatchArrayMatcher < BaseMatcher
      def matches?(actual)
        @actual = actual
        return false unless actual.respond_to?(:to_a)

        remaining = actual.to_a.dup
        @expected.all? do |item|
          idx = remaining.index { |el| item == el || item === el }
          idx ? remaining.delete_at(idx) && true : false
        end && remaining.empty?
      end

      def failure_message
        "Expected #{@actual.inspect} to contain exactly #{@expected.inspect} (in any order)"
      end
    end

    class HaveAttributesMatcher < BaseMatcher
      def matches?(actual)
        @actual = actual
        @mismatches = {}
        @expected.each do |attr, value|
          unless actual.respond_to?(attr)
            @mismatches[attr] = :no_method
            next
          end
          actual_value = actual.public_send(attr)
          @mismatches[attr] = actual_value unless value == actual_value || value === actual_value
        end
        @mismatches.empty?
      end

      def failure_message
        details = @mismatches.map do |attr, val|
          if val == :no_method
            "#{attr}: (does not respond)"
          else
            "#{attr}: expected #{@expected[attr].inspect}, got #{val.inspect}"
          end
        end
        "Expected #{@actual.inspect} to have attributes #{@expected.inspect}:\n  #{details.join("\n  ")}"
      end
    end

    class AllMatcher < BaseMatcher
      def initialize(inner)
        super()
        @inner = inner
      end

      def matches?(actual)
        @actual = actual
        @failed_index = nil
        actual.each_with_index do |item, idx|
          next if @inner.matches?(item)

          @failed_index = idx
          @failed_message = @inner.failure_message
          return false
        end
        true
      end

      def failure_message
        "Expected all elements to match, but element at index #{@failed_index} failed: #{@failed_message}"
      end
    end

    class SatisfyMatcher < BaseMatcher
      def initialize(description = nil, &block)
        super(nil)
        @description = description
        @block = block
      end

      def matches?(actual)
        @actual = actual
        !!@block.call(actual)
      end

      def failure_message
        "Expected #{@actual.inspect} to satisfy #{@description || "the given block"}"
      end
    end

    class BeWithinMatcher < BaseMatcher
      def initialize(delta)
        super(delta)
        @delta = delta
      end

      def of(value)
        @center = value
        self
      end

      def percent_of(value)
        @center = value
        @delta = value.abs * @expected / 100.0
        self
      end

      def matches?(actual)
        raise ArgumentError, "be_within requires .of(value)" unless defined?(@center)

        @actual = actual
        (actual - @center).abs <= @delta
      end

      def failure_message
        "Expected #{@actual.inspect} to be within #{@delta} of #{@center}"
      end
    end

    class StartWithMatcher < BaseMatcher
      def matches?(actual)
        @actual = actual
        if actual.respond_to?(:start_with?)
          actual.start_with?(@expected)
        elsif actual.is_a?(Array)
          actual.first(Array(@expected).size) == Array(@expected)
        else
          false
        end
      end

      def failure_message
        "Expected #{@actual.inspect} to start with #{@expected.inspect}"
      end
    end

    class EndWithMatcher < BaseMatcher
      def matches?(actual)
        @actual = actual
        if actual.respond_to?(:end_with?)
          actual.end_with?(@expected)
        elsif actual.is_a?(Array)
          actual.last(Array(@expected).size) == Array(@expected)
        else
          false
        end
      end

      def failure_message
        "Expected #{@actual.inspect} to end with #{@expected.inspect}"
      end
    end

    class OutputMatcher < BaseMatcher
      def initialize(expected = nil)
        super
        @stream = :stdout
      end

      def to_stdout
        @stream = :stdout
        self
      end

      def to_stderr
        @stream = :stderr
        self
      end

      def matches?(block)
        raise ArgumentError, "output matcher requires a block" unless block.respond_to?(:call)

        @captured = capture(block)
        if @expected.nil?
          !@captured.empty?
        elsif @expected.is_a?(Regexp)
          @expected.match?(@captured)
        else
          @captured.include?(@expected)
        end
      end

      def failure_message
        "Expected block to output #{@expected ? @expected.inspect : "something"} to #{@stream}, got #{@captured.inspect}"
      end

      private

      def capture(block)
        require "stringio"
        captured = StringIO.new
        if @stream == :stdout
          original = $stdout
          $stdout = captured
          begin
            block.call
          ensure
            $stdout = original
          end
        else
          original = $stderr
          $stderr = captured
          begin
            block.call
          ensure
            $stderr = original
          end
        end
        captured.string
      end
    end

    class YieldControlMatcher < BaseMatcher
      def matches?(block)
        @yielded = 0
        probe = ->(*) { @yielded += 1 }
        block.call(probe)
        @yielded.positive?
      end

      def failure_message
        "Expected block to yield control, but it did not"
      end

      def failure_message_when_negated
        "Expected block not to yield control, but it yielded #{@yielded} time(s)"
      end
    end

    class YieldWithArgsMatcher < BaseMatcher
      def initialize(*expected_args)
        super(expected_args)
        @expected_args = expected_args
      end

      def matches?(block)
        @yielded_args = nil
        probe = ->(*args) { @yielded_args = args }
        block.call(probe)
        return false if @yielded_args.nil?
        return true if @expected_args.empty?
        return false unless @yielded_args.size == @expected_args.size

        @expected_args.zip(@yielded_args).all? { |e, a| e == a || e === a }
      end

      def failure_message
        if @yielded_args.nil?
          "Expected block to yield with args #{@expected_args.inspect}, but it did not yield"
        else
          "Expected block to yield with args #{@expected_args.inspect}, got #{@yielded_args.inspect}"
        end
      end
    end

    class YieldSuccessiveArgsMatcher < BaseMatcher
      def initialize(*expected_args)
        super(expected_args)
        @expected_args = expected_args
      end

      def matches?(block)
        @yielded = []
        probe = ->(*args) { @yielded << (args.size == 1 ? args.first : args) }
        block.call(probe)
        return false unless @yielded.size == @expected_args.size

        @expected_args.zip(@yielded).all? { |e, a| e == a || e === a }
      end

      def failure_message
        "Expected block to yield successive args #{@expected_args.inspect}, got #{@yielded.inspect}"
      end
    end

    class CustomMatcher < BaseMatcher
      def initialize(name, expected_args, &definition_block)
        super(expected_args)
        @name = name
        @expected_args = expected_args
        @definition_block = definition_block
        @match_proc = nil
        @failure_message_proc = nil
        @negated_failure_message_proc = nil
        @description_proc = nil
        @chains = {}
        instance_exec(*expected_args, &definition_block) if definition_block
      end

      def match(&block)
        @match_proc = block
      end

      # DSL form (with block) stores the message proc; query form (no
      # block) returns the rendered message.
      def failure_message(&block)
        if block
          @failure_message_proc = block
          return
        end
        if @failure_message_proc
          instance_exec(@actual, &@failure_message_proc)
        else
          "Expected #{@actual.inspect} to #{description}"
        end
      end

      def failure_message_when_negated(&block)
        if block
          @negated_failure_message_proc = block
          return
        end
        if @negated_failure_message_proc
          instance_exec(@actual, &@negated_failure_message_proc)
        else
          "Expected #{@actual.inspect} not to #{description}"
        end
      end

      def description(&block)
        if block
          @description_proc = block
          return
        end
        @description_proc ? instance_exec(&@description_proc) : @name.to_s.tr("_", " ")
      end

      def chain(name, &block)
        matcher = self
        define_singleton_method(name) do |*args|
          matcher.instance_variable_get(:@chains)[name] = args
          matcher.instance_exec(*args, &block) if block
          matcher
        end
      end

      def matches?(actual)
        @actual = actual
        @match_proc ? instance_exec(actual, &@match_proc) : true
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
    alias be_falsey be_falsy

    def be_a(klass)
      BeAKindOfMatcher.new(klass)
    end
    alias be_an be_a
    alias be_a_kind_of be_a
    alias be_kind_of be_a

    def be_an_instance_of(klass)
      BeAnInstanceOfMatcher.new(klass)
    end
    alias be_instance_of be_an_instance_of

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

    def have_http_status(expected)
      HaveHttpStatusMatcher.new(expected)
    end

    def match(expected)
      MatchMatcher.new(expected)
    end

    def match_array(expected)
      MatchArrayMatcher.new(expected.to_a)
    end

    def contain_exactly(*items)
      MatchArrayMatcher.new(items)
    end

    def have_attributes(expected)
      HaveAttributesMatcher.new(expected)
    end

    def all(matcher)
      AllMatcher.new(matcher)
    end

    def satisfy(description = nil, &block)
      SatisfyMatcher.new(description, &block)
    end

    def be_within(delta)
      BeWithinMatcher.new(delta)
    end

    def start_with(expected)
      StartWithMatcher.new(expected)
    end

    def end_with(expected)
      EndWithMatcher.new(expected)
    end

    def output(expected = nil)
      OutputMatcher.new(expected)
    end

    def yield_control
      YieldControlMatcher.new
    end

    def yield_with_args(*args)
      YieldWithArgsMatcher.new(*args)
    end

    def yield_successive_args(*args)
      YieldSuccessiveArgsMatcher.new(*args)
    end

    def self.define(name, &block)
      define_method(name) do |*args|
        CustomMatcher.new(name, args, &block)
      end
    end

    def method_missing(name, *args, **kwargs, &block)
      case name
      when /\Abe_(.+)\z/
        PredicateMatcher.new(:"#{Regexp.last_match(1)}?", "be #{Regexp.last_match(1).tr("_", " ")}", *args, **kwargs, &block)
      when /\Ahave_(.+)\z/
        PredicateMatcher.new(:"has_#{Regexp.last_match(1)}?", "have #{Regexp.last_match(1).tr("_", " ")}", *args, **kwargs, &block)
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      name.to_s.match?(/\A(be|have)_.+\z/) || super
    end
  end
end

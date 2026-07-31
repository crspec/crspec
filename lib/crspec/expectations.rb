# frozen_string_literal: true

require_relative "matchers"

module Crspec
  class ExpectationNotMetError < StandardError; end

  class MultipleExpectationsNotMetError < ExpectationNotMetError
    attr_reader :failures

    def initialize(failures)
      @failures = failures
      summary = failures.each_with_index.map { |msg, i| "  #{i + 1}) #{msg}" }.join("\n")
      super("Got #{failures.size} failure(s):\n#{summary}")
    end
  end

  # Fiber-local failure accumulator backing aggregate_failures.
  module FailureAggregator
    STORAGE_KEY = :crspec_failure_aggregator

    def self.active?
      !Fiber[STORAGE_KEY].nil?
    end

    def self.record(message)
      Fiber[STORAGE_KEY] << message
    end

    def self.aggregate
      previous = Fiber[STORAGE_KEY]
      Fiber[STORAGE_KEY] = []
      begin
        yield
        failures = Fiber[STORAGE_KEY]
        raise MultipleExpectationsNotMetError, failures if failures.size > 1
        raise ExpectationNotMetError, failures.first if failures.size == 1
      ensure
        Fiber[STORAGE_KEY] = previous
      end
    end
  end

  class ExpectationTarget
    def initialize(actual)
      @actual = actual
    end

    def to(matcher = nil, &block)
      matcher ||= block
      return matcher.setup_expect(@actual) if matcher.respond_to?(:setup_expect)

      unless matcher.matches?(@actual)
        fail_with(matcher.failure_message)
        return false
      end

      true
    end

    def not_to(matcher = nil, &block)
      matcher ||= block
      if matcher.matches?(@actual)
        msg = matcher.respond_to?(:failure_message_when_negated) ? matcher.failure_message_when_negated : "Expected matcher not to match"
        fail_with(msg)
        return false
      end
      true
    end

    alias to_not not_to

    private

    def fail_with(message)
      if FailureAggregator.active?
        FailureAggregator.record(message)
      else
        raise ExpectationNotMetError, message
      end
    end
  end

  module Expectations
    include Matchers

    ExpectationNotMetError = Crspec::ExpectationNotMetError

    UNDEFINED = Object.new.freeze

    def expect(value = UNDEFINED, &block)
      actual = value.equal?(UNDEFINED) ? block : value
      ExpectationTarget.new(actual)
    end

    def is_expected
      expect(subject)
    end

    def aggregate_failures(_label = nil, &block)
      FailureAggregator.aggregate(&block)
    end
  end
end

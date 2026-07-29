# frozen_string_literal: true

require_relative "matchers"

module Crspec
  class ExpectationNotMetError < StandardError; end

  class ExpectationTarget
    def initialize(actual)
      @actual = actual
    end

    def to(matcher = nil, &block)
      matcher ||= block
      return matcher.setup_expect(@actual) if matcher.respond_to?(:setup_expect)

      raise ExpectationNotMetError, matcher.failure_message unless matcher.matches?(@actual)

      true
    end

    def not_to(matcher = nil, &block)
      matcher ||= block
      if matcher.matches?(@actual)
        msg = matcher.respond_to?(:failure_message_when_negated) ? matcher.failure_message_when_negated : "Expected matcher not to match"
        raise ExpectationNotMetError, msg
      end
      true
    end

    alias to_not not_to
  end

  module Expectations
    include Matchers

    def expect(value = nil, &block)
      ExpectationTarget.new(value || block)
    end
  end
end

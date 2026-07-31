# frozen_string_literal: true

module Crspec
  # Registry of shared example groups / contexts. Registration happens at
  # load time (single-threaded); lookups at group-definition time. Blocks
  # are re-evaluated in the including group, so no state is shared between
  # examples — parallel-safe by construction.
  module SharedRegistry
    class << self
      def registry
        @registry ||= {}
      end

      def register(name, block)
        registry[name.to_s] = block
      end

      def fetch(name)
        registry[name.to_s] or raise ArgumentError,
                                     "Could not find shared examples or context #{name.inspect}"
      end

      def reset!
        @registry = {}
      end
    end
  end

  def self.shared_examples(name, &block)
    SharedRegistry.register(name, block)
  end

  def self.shared_context(name, &block)
    SharedRegistry.register(name, block)
  end

  class << self
    alias shared_examples_for shared_examples
  end

  module SharedDSL
    def shared_examples(name, &block)
      Crspec::SharedRegistry.register(name, block)
    end
    alias shared_examples_for shared_examples
    alias shared_context shared_examples

    def include_context(name, *args)
      block = Crspec::SharedRegistry.fetch(name)
      if args.empty?
        instance_eval(&block)
      else
        instance_exec(*args, &block)
      end
    end
    alias include_examples include_context

    def it_behaves_like(name, *args)
      block = Crspec::SharedRegistry.fetch(name)
      child = describe("behaves like #{name}") {}
      if args.empty?
        child.instance_eval(&block)
      else
        child.instance_exec(*args, &block)
      end
      child
    end
    alias it_should_behave_like it_behaves_like
  end
end

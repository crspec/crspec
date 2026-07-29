# frozen_string_literal: true

require_relative "expectations"
require_relative "example"
require_relative "mock/double"

module Crspec
  class ExampleGroup
    include Expectations
    include Mock::DSL

    attr_reader :description, :metadata, :parent, :examples, :children, :before_hooks, :after_hooks

    def initialize(description, metadata = {}, parent = nil)
      @description = description
      @metadata = metadata.freeze
      @parent = parent
      @examples = []
      @children = []
      @before_hooks = []
      @after_hooks = []
      @let_blocks = {}
      @eager_lets = []
    end

    def self.define(description, metadata = {}, parent = nil, &block)
      group = new(description, metadata, parent)
      group.instance_eval(&block) if block
      group
    end

    def describe(description, metadata = {}, &block)
      child = self.class.define(description, metadata, self, &block)
      @children << child
      child
    end
    alias context describe

    def it(description = nil, metadata = {}, &block)
      example = Example.new(description || "unnamed example", metadata, self, block)
      @examples << example
      example
    end
    alias specify it

    def let(name, &block)
      @let_blocks[name.to_sym] = block
    end

    def let!(name, &block)
      let(name, &block)
      @eager_lets << name.to_sym
    end

    def subject(name = nil, &block)
      if name
        let(name, &block)
        let(:subject) { send(name) }
      else
        let(:subject, &block)
      end
    end

    def before(_scope = :each, &block)
      @before_hooks << block
    end

    def after(_scope = :each, &block)
      @after_hooks.unshift(block)
    end

    def ancestor_hooks(type)
      hooks = []
      curr = self
      ancestors = []
      while curr
        ancestors.unshift(curr)
        curr = curr.parent
      end

      ancestors.each do |grp|
        list = type == :before ? grp.before_hooks : grp.after_hooks
        hooks.concat(list)
      end
      hooks
    end

    def ancestor_let_blocks
      blocks = {}
      curr = self
      ancestors = []
      while curr
        ancestors.unshift(curr)
        curr = curr.parent
      end
      ancestors.each do |grp|
        blocks.merge!(grp.instance_variable_get(:@let_blocks))
      end
      blocks
    end

    def ancestor_eager_lets
      eager = []
      curr = self
      while curr
        eager.concat(curr.instance_variable_get(:@eager_lets))
        curr = curr.parent
      end
      eager
    end

    def create_instance(example)
      klass = Class.new do
        include Expectations
        include Mock::DSL

        attr_reader :__crspec_example__

        def initialize(example)
          @__crspec_example__ = example
        end

        def execution_context
          ExecutionContext.current
        end
        alias current_context execution_context

        def described_class
          nil
        end
      end

      lets = ancestor_let_blocks
      lets.each do |let_name, let_proc|
        current_proc = let_proc
        klass.define_method(let_name) do
          ExecutionContext.current.fetch_memoized(let_name) do
            instance_exec(&current_proc)
          end
        end
      end

      inst = klass.new(example)

      # Evaluate eager lets
      eager_lets = ancestor_eager_lets
      eager_lets.each do |name|
        inst.send(name)
      end

      inst
    end
  end
end

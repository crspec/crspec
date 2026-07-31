# frozen_string_literal: true

require_relative "expectations"
require_relative "example"
require_relative "mock/double"
require_relative "configuration"

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
      @included_modules = []
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

    def include(mod)
      @included_modules << mod
    end

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
      hooks.concat(Crspec.configuration.before_hooks) if type == :before

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

      hooks.concat(Crspec.configuration.after_hooks) if type == :after

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

    def ancestor_included_modules
      mods = []
      curr = self
      ancestors = []
      while curr
        ancestors.unshift(curr)
        curr = curr.parent
      end
      ancestors.each do |grp|
        mods.concat(grp.instance_variable_get(:@included_modules) || [])
      end
      mods
    end

    def create_instance(example)
      modules_to_include = (Crspec.configuration.included_modules + ancestor_included_modules).uniq

      klass = Class.new do
        include Expectations
        include Mock::DSL

        modules_to_include.each do |mod|
          include mod
        end

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

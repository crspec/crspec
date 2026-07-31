# frozen_string_literal: true

require_relative "example_group"

module Crspec
  class World
    def self.instance
      @instance ||= new
    end

    def self.reset!
      @instance = new
    end

    attr_reader :example_groups

    def initialize
      @example_groups = []
      @frozen = false
    end

    def register(group)
      raise Error, "Cannot register example groups after the run has started" if @frozen

      @example_groups << group
    end

    def freeze!
      @frozen = true
      @example_groups.freeze
      self
    end

    def frozen?
      @frozen
    end
  end

  def self.describe(*args, **kwargs, &block)
    metadata = kwargs.dup
    metadata.merge!(args.pop) if args.last.is_a?(Hash)
    if metadata[:type].nil? && Crspec.configuration.infer_spec_type?
      loc = caller_locations(1, 10).find { |l| l.path.include?("spec/") }
      if loc
        inferred = Crspec.configuration.infer_type_for_file_path(loc.path)
        metadata[:type] = inferred if inferred
      end
    end
    described = args.first.is_a?(Module) ? args.first : nil
    description = described && args.size == 1 ? described : args.map(&:to_s).join(" ")
    group = ExampleGroup.new(description, metadata, nil)
    group.described_module = described
    group.instance_eval(&block) if block
    World.instance.register(group)
    group
  end

  def self.world
    World.instance
  end

  def self.reset!
    World.reset!
  end

  def self.freeze_world!
    World.instance.freeze!
  end

  def self.xdescribe(*args, **kwargs, &block)
    describe(*args, **kwargs, &block).mark_pending!
  end

  def self.fdescribe(*args, **kwargs, &block)
    describe(*args, **kwargs, &block).mark_focused!
  end

  module DSL
    def shared_examples(name, &block)
      Crspec.shared_examples(name, &block)
    end
    alias shared_examples_for shared_examples
    alias shared_context shared_examples

    def describe(*args, **kwargs, &block)
      Crspec.describe(*args, **kwargs, &block)
    end

    def xdescribe(*args, **kwargs, &block)
      Crspec.xdescribe(*args, **kwargs, &block)
    end
    alias xcontext xdescribe

    def fdescribe(*args, **kwargs, &block)
      Crspec.fdescribe(*args, **kwargs, &block)
    end
    alias fcontext fdescribe
  end
end

main = TOPLEVEL_BINDING.eval("self")
main.extend(Crspec::DSL)
include Crspec::DSL

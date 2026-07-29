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
    end

    def register(group)
      @example_groups << group
    end
  end

  def self.describe(description, metadata = {}, &block)
    group = ExampleGroup.define(description, metadata, nil, &block)
    World.instance.register(group)
    group
  end

  def self.world
    World.instance
  end

  def self.reset!
    World.reset!
  end
end

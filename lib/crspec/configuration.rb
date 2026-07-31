# frozen_string_literal: true

require "etc"

module Crspec
  class Configuration
    attr_accessor :concurrency, :use_transactional_fixtures, :formatter
    attr_reader :before_hooks, :after_hooks, :around_hooks, :included_modules

    def initialize
      @concurrency = Etc.nprocessors
      @use_transactional_fixtures = true
      @formatter = nil
      @before_hooks = []
      @after_hooks = []
      @around_hooks = []
      @included_modules = []
      @infer_spec_type = false
    end

    def before(_scope = :each, &block)
      @before_hooks << block
    end

    def after(_scope = :each, &block)
      @after_hooks.unshift(block)
    end

    def around(_scope = :each, &block)
      @around_hooks << block
    end

    def include(mod)
      @included_modules << mod
    end

    def infer_spec_type_from_file_location!
      @infer_spec_type = true
    end

    def infer_spec_type?
      !!@infer_spec_type
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration if block_given?
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end

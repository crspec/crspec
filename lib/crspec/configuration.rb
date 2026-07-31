# frozen_string_literal: true

require "etc"

module Crspec
  class MigrationError < StandardError; end

  class Configuration
    attr_accessor :concurrency, :fibers, :use_transactional_fixtures, :formatter, :example_status_persistence_file_path, :fixture_paths
    attr_writer :file_fixture_path
    attr_reader :before_hooks, :after_hooks, :around_hooks, :included_modules

    def initialize
      @concurrency = Etc.nprocessors
      @fibers = 1
      @use_transactional_fixtures = true
      @formatter = nil
      @before_hooks = []
      @after_hooks = []
      @around_hooks = []
      @included_modules = []
      @infer_spec_type = false
      @fixture_paths = []
      @file_fixture_path = nil
    end

    def file_fixture_path
      @file_fixture_path || File.join("spec", "fixtures", "files")
    end

    def before(*args, **kwargs, &block)
      reject_serial_scope!(:before, args)
      @before_hooks << { block: block, filters: args, kwfilters: kwargs }
    end

    def after(*args, **kwargs, &block)
      reject_serial_scope!(:after, args)
      @after_hooks.unshift({ block: block, filters: args, kwfilters: kwargs })
    end

    def around(*args, **kwargs, &block)
      @around_hooks << { block: block, filters: args, kwfilters: kwargs }
    end

    def include(mod, *filters, **kwfilters)
      @included_modules << { module: mod, filters: filters, kwfilters: kwfilters }
    end

    def infer_spec_type_from_file_location!
      @infer_spec_type = true
    end

    def infer_spec_type?
      !!@infer_spec_type
    end

    def infer_type_for_file_path(file_path)
      return nil unless @infer_spec_type
      case file_path.to_s
      when %r{spec/controllers/} then :controller
      when %r{spec/requests/}, %r{spec/api/} then :request
      when %r{spec/models/} then :model
      when %r{spec/helpers/} then :helper
      when %r{spec/system/} then :system
      when %r{spec/views/} then :view
      when %r{spec/components/} then :component
      when %r{spec/mailers/} then :mailer
      when %r{spec/jobs/} then :job
      when %r{spec/services/} then :service
      end
    end

    def filter_rails_from_backtrace!
    end

    def define_derived_metadata(*args)
    end

    def expect_with(*args)
    end

    def mock_with(*args)
    end

    private

    def reject_serial_scope!(hook_name, args)
      scope = args.first
      return unless scope.is_a?(Symbol) && %i[all context suite].include?(scope)

      raise MigrationError, <<~MSG
        config.#{hook_name}(:#{scope}) is not supported by Crspec: shared state
        across examples is inherently serial and breaks the concurrent
        execution model. Use config.#{hook_name}(:each) or let/let! instead.
      MSG
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

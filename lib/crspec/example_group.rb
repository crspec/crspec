# frozen_string_literal: true

require_relative "expectations"
require_relative "example"
require_relative "mock/double"
require_relative "configuration"
require_relative "file_fixtures"
require_relative "shared_examples"

module Crspec
  class ExampleGroup
    include Expectations
    include Mock::DSL
    include SharedDSL

    attr_reader :description, :metadata, :parent, :examples, :children, :before_hooks, :after_hooks, :around_hooks
    attr_accessor :described_module

    def initialize(description, metadata = {}, parent = nil)
      @description = description
      @described_module = description.is_a?(Module) ? description : nil
      @metadata = metadata.freeze
      @parent = parent
      @examples = []
      @children = []
      @before_hooks = []
      @after_hooks = []
      @around_hooks = []
      @let_blocks = {}
      @eager_lets = []
      @included_modules = []
    end

    def self.define(description, metadata = {}, parent = nil, &block)
      group = new(description, metadata, parent)
      group.instance_eval(&block) if block
      group
    end

    def describe(*args, **kwargs, &block)
      metadata = kwargs.dup
      metadata.merge!(args.pop) if args.last.is_a?(Hash)
      described = args.first.is_a?(Module) ? args.first : nil
      description = described && args.size == 1 ? described : args.map(&:to_s).join(" ")
      child = self.class.new(description, metadata, self)
      child.described_module = described
      child.instance_eval(&block) if block
      @children << child
      child
    end
    alias context describe

    def xdescribe(*args, **kwargs, &block)
      child = describe(*args, **kwargs, &block)
      child.mark_pending!
      child
    end
    alias xcontext xdescribe

    def fdescribe(*args, **kwargs, &block)
      child = describe(*args, **kwargs, &block)
      child.mark_focused!
      child
    end
    alias fcontext fdescribe

    def it(description = nil, metadata = {}, &block)
      example = Example.new(description || "unnamed example", metadata, self, block,
                            pending: pending?)
      @examples << example
      example
    end
    alias specify it

    def xit(description = nil, metadata = {}, &block)
      example = Example.new(description || "unnamed example", metadata, self, block,
                            pending: true)
      @examples << example
      example
    end
    alias pending xit
    alias skip xit

    def fit(description = nil, metadata = {}, &block)
      example = it(description, metadata, &block)
      example.focused = true
      example
    end

    def mark_pending!
      @pending = true
      @examples.each { |ex| ex.instance_variable_set(:@pending, true) }
      @children.each(&:mark_pending!)
      self
    end

    def pending?
      !!@pending || (parent ? parent.pending? : false)
    end

    def mark_focused!
      @focused = true
      @examples.each { |ex| ex.focused = true }
      @children.each(&:mark_focused!)
      self
    end

    def focused?
      !!@focused
    end

    def include(mod)
      @included_modules << mod
    end

    def render_views(*args)
    end

    def private(*args)
    end

    def public(*args)
    end

    def protected(*args)
    end

    def attr_reader(*names)
      names.each do |name|
        let(name) { instance_variable_get("@#{name}") }
      end
    end

    def attr_writer(*names)
      names.each do |name|
        define_method("#{name}=") { |val| instance_variable_set("@#{name}", val) }
      end
    end

    def attr_accessor(*names)
      attr_reader(*names)
      attr_writer(*names)
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

    FORBIDDEN_HOOK_SCOPES = %i[all context suite].freeze

    def before(*args, **kwargs, &block)
      reject_serial_scope!(:before, args)
      @before_hooks << { block: block, filters: args, kwfilters: kwargs }
    end

    def after(*args, **kwargs, &block)
      reject_serial_scope!(:after, args)
      @after_hooks.unshift({ block: block, filters: args, kwfilters: kwargs })
    end

    def reject_serial_scope!(hook_name, args)
      scope = args.first
      return unless scope.is_a?(Symbol) && FORBIDDEN_HOOK_SCOPES.include?(scope)

      raise MigrationError, <<~MSG
        #{hook_name}(:#{scope}) is not supported by Crspec: shared state across
        examples is inherently serial and breaks the P processes x N threads x
        M fibers execution model.

        Migrate to per-example setup instead:
          - use before(:each) if the setup is cheap
          - use let/let! for lazily-built (memoized per example) values

        Run `crspec-transpile --analyze` on your suite to find and rewrite all
        occurrences automatically.
      MSG
    end

    def around(*args, **kwargs, &block)
      @around_hooks << { block: block, filters: args, kwfilters: kwargs }
    end

    def finalize!
      ancestor_metadata
      ancestor_let_blocks
      ancestor_eager_lets
      ancestor_included_modules
      described_class
      %i[before after around].each { |type| raw_hooks_for(type) }

      example_types = examples.map { |ex| effective_type_for(ex) }.uniq
      example_types.each do |type|
        %i[before after around].each { |hook_type| filtered_hooks(hook_type, type) }
        modules_for_type(type)
        example_class_for(type)
      end

      children.each(&:finalize!)
      self
    end

    def ancestor_hooks(type, example = nil)
      filtered_hooks(type, example ? effective_type_for(example) : ancestor_metadata[:type])
    end

    def ancestor_let_blocks
      @ancestor_let_blocks ||= begin
        blocks = {}
        ancestor_chain.each do |grp|
          blocks.merge!(grp.instance_variable_get(:@let_blocks))
        end
        unless blocks.key?(:subject)
          desc_cls = described_class
          if desc_cls.is_a?(Class)
            blocks[:subject] = proc { desc_cls.new rescue nil }
          elsif desc_cls
            blocks[:subject] = proc { desc_cls }
          end
        end
        blocks.freeze
      end
    end

    def ancestor_eager_lets
      @ancestor_eager_lets ||= ancestor_chain.flat_map do |grp|
        grp.instance_variable_get(:@eager_lets)
      end.freeze
    end

    def ancestor_included_modules
      @ancestor_included_modules ||= ancestor_chain.flat_map do |grp|
        grp.instance_variable_get(:@included_modules) || []
      end.freeze
    end

    def ancestor_metadata
      @ancestor_metadata ||= begin
        meta = {}
        ancestor_chain.each do |grp|
          meta.merge!(grp.metadata || {})
        end
        meta.freeze
      end
    end

    def modules_for_example(example)
      modules_for_type(effective_type_for(example))
    end

    def described_class
      return @described_class if defined?(@described_class)

      @described_class = begin
        found = nil
        curr = self
        while curr
          if curr.described_module
            found = curr.described_module
            break
          end
          curr = curr.parent
        end
        found
      end
    end

    def effective_type_for(example)
      meta = example.metadata || {}
      meta.key?(:type) ? meta[:type] : ancestor_metadata[:type]
    end

    def run_eager_lets(instance)
      ancestor_eager_lets.each do |name|
        instance.send(name)
      end
    end

    def create_instance(example)
      klass = example_class_for(effective_type_for(example))
      inst = klass.new(example)

      klass.setup_callbacks.each do |cb|
        if cb.is_a?(Symbol) || cb.is_a?(String)
          inst.send(cb)
        elsif cb.respond_to?(:call)
          inst.instance_exec(&cb)
        end
      end

      inst
    end

    private

    def ancestor_chain
      @ancestor_chain ||= begin
        chain = []
        curr = self
        while curr
          chain.unshift(curr)
          curr = curr.parent
        end
        chain.freeze
      end
    end

    def raw_hooks_for(type)
      @raw_hooks_for ||= {}
      @raw_hooks_for[type] ||= begin
        raw_hooks = []
        if type == :before
          raw_hooks.concat(Crspec.configuration.before_hooks)
        elsif type == :around
          raw_hooks.concat(Crspec.configuration.around_hooks)
        end

        ancestor_chain.each do |grp|
          list = case type
                 when :before then grp.before_hooks
                 when :after then grp.after_hooks
                 when :around then grp.around_hooks
                 end
          raw_hooks.concat(list)
        end

        raw_hooks.concat(Crspec.configuration.after_hooks) if type == :after
        raw_hooks.freeze
      end
    end

    def filtered_hooks(hook_type, meta_type)
      @filtered_hooks ||= {}
      @filtered_hooks[[hook_type, meta_type]] ||= raw_hooks_for(hook_type).filter_map do |hook|
        if hook.is_a?(Hash)
          blk = hook[:block]
          kw = hook[:kwfilters] || {}
          filters = hook[:filters] || []

          target_type = kw[:type] || (filters.first.is_a?(Hash) && filters.first[:type])
          next if target_type && meta_type != target_type

          blk
        else
          hook
        end
      end.freeze
    end

    def modules_for_type(meta_type)
      @modules_for_type ||= {}
      @modules_for_type[meta_type] ||= begin
        all_entries = Crspec.configuration.included_modules + ancestor_included_modules

        all_entries.filter_map do |entry|
          if entry.is_a?(Hash)
            mod = entry[:module]
            kw = entry[:kwfilters] || {}
            filters = entry[:filters] || []

            target_type = kw[:type] || (filters.first.is_a?(Hash) && filters.first[:type])
            next if target_type && meta_type != target_type

            mod
          else
            entry
          end
        end.uniq.freeze
      end
    end

    def example_class_for(meta_type)
      @example_class_for ||= {}
      @example_class_for[meta_type] ||= build_example_class(meta_type)
    end

    def build_example_class(meta_type)
      modules_to_include = modules_for_type(meta_type)
      desc_cls = described_class

      klass = Class.new do
        define_singleton_method(:spec_type) { meta_type }

        class << self
          attr_writer :controller_class

          def controller_class
            @controller_class
          end

          def setup(*args, &block)
            @setup_callbacks ||= []
            @setup_callbacks << (block || args.first)
          end

          def teardown(*args, &block)
            @teardown_callbacks ||= []
            @teardown_callbacks << (block || args.first)
          end

          def setup_callbacks
            @setup_callbacks || []
          end

          def teardown_callbacks
            @teardown_callbacks || []
          end
        end

        include Expectations
        include Mock::DSL
        include FileFixtures

        if meta_type == :controller
          include ActionController::TestCase::Behavior if defined?(ActionController::TestCase::Behavior)
        elsif meta_type == :request
          include ActionDispatch::Integration::Runner if defined?(ActionDispatch::Integration::Runner)
          include ActionDispatch::IntegrationTest::Behavior if defined?(ActionDispatch::IntegrationTest::Behavior)
        end

        modules_to_include.each do |mod|
          include mod
        end

        attr_reader :__crspec_example__

        define_method(:initialize) do |example|
          @__crspec_example__ = example
          meta_type = self.class.spec_type
          is_controller = meta_type == :controller || (desc_cls.is_a?(Class) && desc_cls.ancestors.map(&:to_s).include?("ActionController::Metal"))
          if is_controller
            ctrl_cls = desc_cls
            begin
              @controller = ctrl_cls.new if ctrl_cls.is_a?(Class)
            rescue StandardError
              # ignore
            end
            if defined?(ActionDispatch::TestRequest)
              @request = ActionDispatch::TestRequest.create rescue nil
              @response = ActionDispatch::TestResponse.new rescue nil
            end
            if defined?(::Rails) && ::Rails.application
              @routes = ::Rails.application.routes
            end
          end
        end

        def execution_context
          ExecutionContext.current
        end
        alias current_context execution_context

        define_method(:described_class) do
          desc_cls
        end
      end

      klass.controller_class = desc_cls if desc_cls.is_a?(Class)

      ancestor_let_blocks.each do |let_name, let_proc|
        current_proc = let_proc
        klass.define_method(let_name) do
          ExecutionContext.current.fetch_memoized(let_name) do
            instance_exec(&current_proc)
          end
        end
      end

      klass
    end
  end
end

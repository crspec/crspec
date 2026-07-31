# frozen_string_literal: true

require "securerandom"

module Crspec
  class Example
    attr_reader :id, :description, :metadata, :example_group, :block, :status, :error, :execution_time, :file_path, :line_number
    attr_accessor :focused

    def initialize(description, metadata, example_group, block, pending: false, location: nil)
      @id = SecureRandom.uuid
      @description = description
      @metadata = metadata.freeze
      @example_group = example_group
      @block = block
      @status = :pending
      @pending = pending || block.nil? || metadata[:skip] || metadata[:pending] ? true : false
      @focused = metadata[:focus] ? true : false
      @error = nil
      @execution_time = 0
      location ||= block&.source_location
      @file_path, @line_number = location if location
    end

    def focused?
      @focused
    end

    def pending?
      @pending
    end

    def persistence_key
      @persistence_key ||= begin
        parts = []
        group = @example_group
        while group
          parts.unshift(group.description.to_s)
          group = group.parent
        end
        parts << @description.to_s
        parts.join(" > ")
      end
    end

    class ExampleInvocation
      def initialize(runner_proc)
        @runner_proc = runner_proc
      end

      def execute!
        @runner_proc.call
      end
      alias run execute!
      alias call execute!
    end

    def execute!
      return if @pending

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      instance = @example_group.create_instance(self)

      begin
        around_hooks = @example_group.ancestor_hooks(:around, self)
        run_around_hooks(instance, around_hooks) do
          @example_group.run_eager_lets(instance)
          run_hooks(instance, :before)
          instance.instance_exec(&@block) if @block
          @status = :passed
        end
      rescue StandardError, ExpectationNotMetError => e
        @status = :failed
        @error = e
      ensure
        begin
          run_hooks(instance, :after)
        rescue StandardError => e
          if @status == :passed
            @status = :failed
            @error = e
          end
        end
        @execution_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      end
    end

    private

    def run_around_hooks(instance, hooks, &final_block)
      if hooks.empty?
        final_block.call
      else
        head, *tail = hooks
        inv = ExampleInvocation.new(-> { run_around_hooks(instance, tail, &final_block) })
        instance.instance_exec(inv, &head)
      end
    end

    def run_hooks(instance, type)
      hooks = @example_group.ancestor_hooks(type, self)
      hooks.each do |hook|
        instance.instance_exec(&hook)
      end
    end
  end
end

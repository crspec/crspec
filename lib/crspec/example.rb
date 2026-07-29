# frozen_string_literal: true

require "securerandom"

module Crspec
  class Example
    attr_reader :id, :description, :metadata, :example_group, :block, :status, :error, :execution_time

    def initialize(description, metadata, example_group, block)
      @id = SecureRandom.uuid
      @description = description
      @metadata = metadata.freeze
      @example_group = example_group
      @block = block
      @status = :pending
      @error = nil
      @execution_time = 0
    end

    def execute!
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      instance = @example_group.create_instance(self)

      begin
        run_hooks(instance, :before)
        instance.instance_exec(&@block) if @block
        @status = :passed
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

    def run_hooks(instance, type)
      hooks = @example_group.ancestor_hooks(type)
      hooks.each do |hook|
        instance.instance_exec(&hook)
      end
    end
  end
end

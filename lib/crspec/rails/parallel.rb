# frozen_string_literal: true

require "etc"

module Crspec
  module Rails
    module Parallel
      class << self
        attr_accessor :worker_count, :setup_blocks, :teardown_blocks, :enabled

        def parallelize(workers: :number_of_processors, &block)
          count = case workers
                  when :number_of_processors
                    Etc.nprocessors
                  when Integer
                    workers
                  else
                    Etc.nprocessors
                  end
          @worker_count = count
          @enabled = true
          @setup_blocks ||= []
          @teardown_blocks ||= []

          return unless block_given?

          instance_eval(&block)
        end

        def enabled?
          !!@enabled
        end

        def parallelize_setup(&block)
          @setup_blocks ||= []
          @setup_blocks << block
        end

        def parallelize_teardown(&block)
          @teardown_blocks ||= []
          @teardown_blocks << block
        end

        def setup_worker(worker_number)
          env_num = worker_number == 1 ? "" : worker_number.to_s
          ENV["TEST_ENV_NUMBER"] = env_num
          ENV["PARALLEL_WORKERS"] = (@worker_count || Etc.nprocessors).to_s

          if defined?(ActiveRecord::Base) && ActiveRecord::Base.respond_to?(:connection_db_config)
            setup_active_record_db(worker_number)
          end

          @setup_blocks&.each { |b| b.call(worker_number) }
        end

        def teardown_worker(worker_number)
          @teardown_blocks&.each { |b| b.call(worker_number) }

          return unless defined?(ActiveRecord::Base) && ActiveRecord::Base.respond_to?(:connection_handler)

          begin
            ActiveRecord::Base.connection_handler.clear_all_connections!
          rescue StandardError
            nil
          end
        end

        def reset!
          @enabled = false
          @worker_count = nil
          @setup_blocks = []
          @teardown_blocks = []
        end

        private

        def setup_active_record_db(worker_number)
          return if worker_number == 1

          config = begin
            ActiveRecord::Base.connection_db_config
          rescue StandardError
            nil
          end
          return unless config

          db_name = "#{config.database}_#{worker_number}"
          new_config = config.configuration_hash.merge(database: db_name)
          begin
            ActiveRecord::Base.establish_connection(new_config)
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end

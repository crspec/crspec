# frozen_string_literal: true

module Crspec
  module Rails
    class DatabaseIsolation
      LEASES_KEY = :crspec_db_leases

      class << self
        def wrap_example(example)
          return example.execute! unless active_record_ready?

          pools = writing_pools
          return example.execute! if pools.empty?

          if pools.any? { |pool| sqlite_pool?(pool) }
            serialized_example(pools) { example.execute! }
          else
            savepoint_example { example.execute! }
          end
        end

        def finish_worker
          leases = Fiber[LEASES_KEY]
          return unless leases

          Fiber[LEASES_KEY] = nil
          leases.each do |pool, conn|
            begin
              conn.rollback_transaction while conn.open_transactions.positive?
            rescue StandardError
              nil
            end
            release(pool, conn)
          end
        end

        def handoff_connection(pool)
          Fiber[LEASES_KEY]&.[](pool)
        end

        private

        # PG/MySQL: each worker keeps a leased connection with a root
        # non-joinable transaction; every example runs inside a nested
        # transaction (SAVEPOINT) rolled back afterwards.
        def savepoint_example
          leases = ensure_worker_leases!
          return yield if leases.empty?

          depths = {}
          leases.each do |pool, conn|
            depths[pool] = conn.open_transactions
            conn.begin_transaction(joinable: false)
          end

          begin
            yield
          ensure
            leases.each do |pool, conn|
              base_depth = depths[pool] + 1
              begin
                conn.rollback_transaction while conn.open_transactions >= base_depth
              rescue StandardError
                nil
              end
            end
          end
        end

        # SQLite permits a single writer per database file, so write
        # transactions cannot overlap across worker threads. Examples
        # touching SQLite pools are serialized with per-example
        # transactions; use --processes with per-process databases for
        # SQLite concurrency.
        def serialized_example(pools)
          write_mutex.synchronize do
            leases = {}
            pools.each do |pool|
              conn = lease(pool)
              next unless conn

              conn.begin_transaction(joinable: false)
              leases[pool] = conn
            end

            previous = Fiber[LEASES_KEY]
            Fiber[LEASES_KEY] = leases
            begin
              yield
            ensure
              Fiber[LEASES_KEY] = previous
              leases.each do |pool, conn|
                begin
                  conn.rollback_transaction while conn.open_transactions.positive?
                rescue StandardError
                  nil
                end
                release(pool, conn)
              end
            end
          end
        end

        def write_mutex
          @write_mutex ||= Mutex.new
        end

        def active_record_ready?
          defined?(ActiveRecord::Base) && ActiveRecord::Base.connected?
        end

        def ensure_worker_leases!
          Fiber[LEASES_KEY] ||= begin
            install_handoff!
            writing_pools.each_with_object({}) do |pool, leases|
              conn = lease(pool)
              next unless conn

              conn.begin_transaction(joinable: false)
              leases[pool] = conn
            end
          end
        end

        def writing_pools
          ActiveRecord::Base.connection_handler.connection_pool_list(:writing)
        rescue StandardError
          []
        end

        def sqlite_pool?(pool)
          adapter = pool.db_config.adapter.to_s
          adapter.match?(/sqlite/i)
        rescue StandardError
          false
        end

        def lease(pool)
          install_handoff!
          if pool.respond_to?(:lease_connection)
            pool.lease_connection
          else
            pool.checkout
          end
        rescue StandardError
          nil
        end

        def release(pool, conn)
          if pool.respond_to?(:release_connection)
            pool.release_connection
          else
            pool.checkin(conn)
          end
        rescue StandardError
          nil
        end

        def install_handoff!
          return if @handoff_installed
          return unless defined?(ActiveRecord::ConnectionAdapters::ConnectionPool)

          ActiveRecord::ConnectionAdapters::ConnectionPool.prepend(ConnectionHandoff)
          @handoff_installed = true
        end
      end

      module ConnectionHandoff
        def lease_connection(*args)
          DatabaseIsolation.handoff_connection(self) || super
        end

        def connection(*args)
          DatabaseIsolation.handoff_connection(self) || super
        end

        def release_connection(*args)
          return if DatabaseIsolation.handoff_connection(self)

          super
        end

        def checkin(conn, *args)
          return if DatabaseIsolation.handoff_connection(self) == conn

          super
        end
      end
    end
  end
end

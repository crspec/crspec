# frozen_string_literal: true

module Crspec
  module Rails
    module DatabaseIsolation
      def self.wrap_example(example)
        if defined?(ActiveRecord::Base) && ActiveRecord::Base.respond_to?(:lease_connection)
          connection = ActiveRecord::Base.lease_connection
          connection.begin_transaction(joinable: false)
          savepoint_name = "ex_root"
          connection.create_savepoint(savepoint_name) if connection.respond_to?(:create_savepoint)

          begin
            example.execute!
          ensure
            if connection.respond_to?(:transaction_open?) && connection.transaction_open?
              connection.rollback_transaction
            end
            if ActiveRecord::Base.respond_to?(:connection_handler) && ActiveRecord::Base.connection_handler.respond_to?(:release_connection)
              ActiveRecord::Base.connection_handler.release_connection
            end
          end
        else
          example.execute!
        end
      end
    end
  end
end

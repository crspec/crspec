# frozen_string_literal: true

module Crspec
  module Rails
    class DatabaseIsolation
      def self.wrap_example(example)
        if defined?(ActiveRecord::Base) && ActiveRecord::Base.connected?
          ActiveRecord::Base.connection_pool.with_connection do |conn|
            conn.transaction(requires_new: true) do
              example.execute!
              raise ActiveRecord::Rollback
            end
          end
        else
          example.execute!
        end
      end
    end
  end
end

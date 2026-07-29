# frozen_string_literal: true

require "etc"

module Crspec
  module Rails
    class SystemServer
      def self.start_concurrent_server!(app = nil, port = 9887)
        @server_mutex ||= Mutex.new
        @server_mutex.synchronize do
          return if @running

          if defined?(Puma::Server)
            rack_app = app || (defined?(::Rails) && ::Rails.respond_to?(:application) ? ::Rails.application : nil)
            return unless rack_app

            events = defined?(Puma::Events) ? Puma::Events.null : nil
            server = Puma::Server.new(rack_app, events, { min_threads: 1, max_threads: Etc.nprocessors })
            server.add_tcp_listener("127.0.0.1", port)
            Thread.new { server.run }
          end
          @running = true
        end
      end

      def self.running?
        !!@running
      end

      def self.reset!
        @running = false
      end
    end
  end
end

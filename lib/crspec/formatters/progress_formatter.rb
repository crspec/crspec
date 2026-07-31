# frozen_string_literal: true

module Crspec
  module Formatters
    class ProgressFormatter
      FLUSH_THRESHOLD = 64
      FLUSH_INTERVAL = 0.2

      def initialize(output = $stdout, color: output.respond_to?(:tty?) && output.tty?)
        @output = output
        @color = color
        @mutex = Mutex.new
        @buffer = +""
        @last_flush = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def example_passed(_example)
        record(@color ? "\e[32m.\e[0m" : ".")
      end

      def example_failed(_example)
        record(@color ? "\e[31mF\e[0m" : "F")
      end

      def example_pending(_example)
        record(@color ? "\e[33m*\e[0m" : "*")
      end

      def start
        @last_flush = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def finish
        chunk = @mutex.synchronize { swap_buffer }
        @output.print(chunk) unless chunk.empty?
        @output.puts
        @output.flush
      end

      private

      def record(token)
        chunk = nil
        @mutex.synchronize do
          @buffer << token
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          if @buffer.size >= FLUSH_THRESHOLD || now - @last_flush >= FLUSH_INTERVAL
            @last_flush = now
            chunk = swap_buffer
          end
        end
        return unless chunk

        @output.print(chunk)
        @output.flush
      end

      def swap_buffer
        chunk = @buffer
        @buffer = +""
        chunk
      end
    end

    class NullFormatter
      def example_passed(_example); end
      def example_failed(_example); end
      def example_pending(_example); end
      def start; end
      def finish; end
    end
  end
end

# frozen_string_literal: true

module Crspec
  module Formatters
    class ProgressFormatter
      def initialize(output = $stdout, color: output.respond_to?(:tty?) && output.tty?)
        @output = output
        @color = color
        @mutex = Mutex.new
      end

      def example_passed(_example)
        @mutex.synchronize do
          @output.print @color ? "\e[32m.\e[0m" : "."
          @output.flush
        end
      end

      def example_failed(_example)
        @mutex.synchronize do
          @output.print @color ? "\e[31mF\e[0m" : "F"
          @output.flush
        end
      end

      def example_pending(_example)
        @mutex.synchronize do
          @output.print @color ? "\e[33m*\e[0m" : "*"
          @output.flush
        end
      end

      def start; end

      def finish
        @mutex.synchronize do
          @output.puts
        end
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

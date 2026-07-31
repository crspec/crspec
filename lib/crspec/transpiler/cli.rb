# frozen_string_literal: true

require_relative "rewriter"
require "optparse"
require "fileutils"

module Crspec
  module Transpiler
    class CLI
      def self.run(args)
        new(args).run
      end

      def initialize(args)
        @args = args
        @mode = :help
        @paths = []
      end

      def run
        parse_options
        case @mode
        when :analyze
          analyze_paths(@paths)
        when :write
          write_paths(@paths)
        else
          Rails.logger.debug "Usage: crspec-transpile [--analyze|--write] <files or directories>"
        end
      end

      private

      def parse_options
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: crspec-transpile [options] <path>"

          opts.on("-a", "--analyze", "Analyze files for thread-unsafe patterns") do
            @mode = :analyze
          end

          opts.on("-w", "--write", "Transpile RSpec files to Crspec in-place") do
            @mode = :write
          end

          opts.on("-h", "--help", "Show help") do
            @mode = :help
          end
        end

        leftovers = parser.parse(@args)
        @paths = leftovers.empty? ? ["spec"] : leftovers
      end

      def find_files(paths)
        files = []
        paths.each do |p|
          if File.directory?(p)
            files.concat(Dir.glob(File.join(p, "**", "*_spec.rb")))
            files.concat(Dir.glob(File.join(p, "**", "*.rb"))) if files.empty?
          elsif File.file?(p)
            files << p
          end
        end
        files.uniq
      end

      def analyze_paths(paths)
        files = find_files(paths)
        total_warnings = 0

        files.each do |file|
          content = File.read(file)
          rewriter = Rewriter.new(content)
          rewriter.transpile
          next if rewriter.warnings.empty?

          Rails.logger.debug { "File: #{file}" }
          rewriter.warnings.each do |w|
            Rails.logger.debug { "  #{w}" }
            total_warnings += 1
          end
        end

        Rails.logger.debug { "Analysis complete. Total warnings found: #{total_warnings}" }
      end

      def write_paths(paths)
        files = find_files(paths)
        count = 0

        files.each do |file|
          content = File.read(file)
          rewriter = Rewriter.new(content)
          new_code = rewriter.transpile

          next unless new_code != content

          File.write(file, new_code)
          Rails.logger.debug { "Transpiled: #{file}" }
          count += 1
        end

        Rails.logger.debug { "Transpilation complete. Updated #{count} file(s)." }
      end
    end
  end
end

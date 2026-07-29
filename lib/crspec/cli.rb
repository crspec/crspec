# frozen_string_literal: true

require "optparse"
require_relative "../crspec"

module Crspec
  class CLI
    def self.run(args)
      new(args).run
    end

    def initialize(args)
      @args = args
      @concurrency = Etc.nprocessors
      @paths = []
    end

    def run
      parse_options
      load_specs
      runner = Runner.new(concurrency: @concurrency)
      groups = Crspec.world.example_groups

      if groups.empty?
        puts "No example groups found."
        return true
      end

      puts "Running Crspec suite with concurrency #{@concurrency}..."
      runner.run(groups)

      puts "\nFinished in #{runner.total_duration.round(4)} seconds"
      puts "#{runner.passed_examples.size + runner.failed_examples.size} examples, #{runner.failed_examples.size} failures"

      unless runner.failed_examples.empty?
        puts "\nFailures:"
        runner.failed_examples.each_with_index do |ex, idx|
          puts "#{idx + 1}) #{ex.description}"
          puts "   Failure/Error: #{ex.error.message}"
          puts "   #{ex.error.backtrace&.first}" if ex.error.backtrace
        end
      end

      runner.success?
    end

    private

    def parse_options
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: crspec [options] [files or directories]"

        opts.on("-c", "--concurrency N", Integer, "Number of concurrent worker threads") do |n|
          @concurrency = n
        end

        opts.on("-h", "--help", "Show help") do
          puts opts
          exit 0
        end
      end

      @paths = parser.parse(@args)
      @paths = ["spec"] if @paths.empty?
    end

    def load_specs
      files = []
      @paths.each do |p|
        if File.directory?(p)
          files.concat(Dir.glob(File.join(p, "**", "*_spec.rb")))
        elsif File.file?(p)
          files << p
        end
      end

      files.uniq.each do |file|
        require File.expand_path(file)
      end
    end
  end
end

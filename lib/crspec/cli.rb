# frozen_string_literal: true

require "optparse"
require_relative "../crspec"
require_relative "generators/init"

module Crspec
  class CLI
    def self.run(args)
      new(args).run
    end

    def initialize(args)
      @args = args
      @concurrency = Crspec.configuration.concurrency
      @fibers = nil
      @paths = []
      @requires = []
      @init_mode = false
      @fail_fast = false
      @seed = nil
      @only_failures = false
      @processes = 1
      @tags = {}
      @locations = []
    end

    def run
      parse_options

      if @init_mode
        created = Generators::Init.generate
        if created.empty?
          puts "No helper files were created (already exists or not a Rails project)."
        else
          created.each { |f| puts "  create #{f}" }
        end
        return true
      end

      load_requires
      load_specs

      concurrency = @concurrency || Crspec.configuration.concurrency
      fibers = @fibers || Crspec.configuration.fibers
      persistence_path = Crspec.configuration.example_status_persistence_file_path ||
                         File.join("tmp", "crspec_status.json")
      multi_process = @processes == :auto || (@processes.is_a?(Integer) && @processes > 1)
      if multi_process && !ProcessRunner.fork_supported?
        if @processes == :auto
          # auto = "use the best multi-core strategy"; on engines without a
          # GVL, threads already are that strategy.
          puts "#{RUBY_ENGINE} has no fork; --processes auto falling back to #{concurrency} threads."
          multi_process = false
        else
          warn "Error: --processes requires fork, which #{RUBY_ENGINE} does not support."
          warn "On #{RUBY_ENGINE} threads use all cores; use -c/--concurrency instead."
          return false
        end
      end
      runner = if multi_process
                 ProcessRunner.new(processes: @processes, concurrency: concurrency,
                                   fibers: fibers, fail_fast: @fail_fast, seed: @seed,
                                   only_failures: @only_failures,
                                   persistence_path: persistence_path)
               else
                 Runner.new(concurrency: concurrency, fibers: fibers, fail_fast: @fail_fast,
                            seed: @seed, only_failures: @only_failures,
                            persistence_path: persistence_path,
                            tags: @tags.empty? ? nil : @tags,
                            locations: @locations.empty? ? nil : @locations)
               end
      groups = Crspec.world.example_groups
      Crspec.world.freeze!

      if groups.empty?
        puts "No example groups found."
        return true
      end

      banner = "Running Crspec suite with concurrency #{concurrency}"
      banner += ", #{@processes == :auto ? 'auto' : @processes} processes" if multi_process
      banner += ", #{fibers} fibers/worker" if fibers && fibers > 1
      banner += ", seed #{@seed}" if @seed
      puts "#{banner}..."
      runner.run(groups)

      puts "\nFinished in #{runner.total_duration.round(4)} seconds"
      total = runner.passed_examples.size + runner.failed_examples.size + runner.pending_examples.size
      summary = "#{total} examples, #{runner.failed_examples.size} failures"
      summary += ", #{runner.pending_examples.size} pending" unless runner.pending_examples.empty?
      puts summary

      unless runner.failed_examples.empty?
        puts "\nFailures:"
        runner.failed_examples.each_with_index do |ex, idx|
          puts "#{idx + 1}) #{ex.description}"
          if ex.respond_to?(:error) && ex.error
            puts "   Failure/Error: #{ex.error.message}"
            puts "   #{ex.error.backtrace&.first}" if ex.error.backtrace
          elsif ex.respond_to?(:error_message)
            puts "   Failure/Error: #{ex.error_message}"
            puts "   #{ex.error_backtrace&.first}" if ex.error_backtrace
          end
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

        opts.on("--fibers M", Integer, "Concurrent example fibers per worker thread (default 1)") do |m|
          @fibers = m
        end

        opts.on("-r", "--require PATH", String, "Require a file before running specs") do |path|
          @requires << path
        end

        opts.on("--init", "Initialize spec_helper.rb (and rails_helper.rb if Rails project)") do
          @init_mode = true
        end

        opts.on("--fail-fast [N]", Integer, "Abort the run after N failures (default 1)") do |n|
          @fail_fast = n || 1
        end

        opts.on("--seed N", Integer, "Randomize example order with the given seed") do |n|
          @seed = n
        end

        opts.on("--only-failures", "Run only examples that failed in the previous run") do
          @only_failures = true
        end

        opts.on("--processes P", String, "Fork P worker processes ('auto' = physical cores)") do |p|
          @processes = p == "auto" ? :auto : Integer(p)
        end

        opts.on("--tag TAG", String, "Run only examples with the given tag (TAG or TAG:VALUE)") do |t|
          key, value = t.split(":", 2)
          @tags[key.to_sym] = value.nil? ? true : parse_tag_value(value)
        end

        opts.on("-h", "--help", "Show help") do
          puts opts
          exit 0
        end
      end

      @paths = parser.parse(@args)
      @paths = ["spec"] if @paths.empty?

      # Extract path:42 line-number filters.
      @paths = @paths.map do |p|
        if p =~ /\A(.+\.rb):(\d+)\z/
          @locations << [Regexp.last_match(1), Regexp.last_match(2).to_i]
          Regexp.last_match(1)
        else
          p
        end
      end
    end

    def parse_tag_value(value)
      case value
      when "true" then true
      when "false" then false
      when /\A\d+\z/ then value.to_i
      else value.to_sym
      end
    end

    def load_requires
      @requires.each do |req|
        require req
      end
    end

    def load_specs
      spec_dir = File.expand_path("spec")
      $LOAD_PATH.unshift(spec_dir) if File.directory?(spec_dir) && !$LOAD_PATH.include?(spec_dir)
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

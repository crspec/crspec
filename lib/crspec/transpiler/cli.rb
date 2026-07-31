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
        @diff = false
        @backup = true
      end

      def run
        parse_options
        case @mode
        when :analyze
          analyze_paths(@paths)
        when :write
          write_paths(@paths)
        when :report
          report_paths(@paths)
        else
          puts "Usage: crspec-transpile [--analyze|--write|--report] [--diff] [--no-backup] <files or directories>"
          true
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

          opts.on("--report", "Print a per-file migration report with safety scores") do
            @mode = :report
          end

          opts.on("--diff", "Dry run: print unified diffs instead of writing") do
            @diff = true
          end

          opts.on("--no-backup", "Do not write .bak backups when transpiling") do
            @backup = false
          end

          opts.on("-h", "--help", "Show help") do
            @mode = :help
          end
        end

        leftovers = parser.parse(@args)
        @paths = leftovers.empty? ? ["spec"] : leftovers
      end

      # Only *_spec.rb plus known helper files are candidates. The old
      # fallback glob (**/*.rb when no spec files matched) could rewrite an
      # entire application tree; it is gone.
      def find_files(paths)
        files = []
        paths.each do |p|
          if File.directory?(p)
            files.concat(Dir.glob(File.join(p, "**", "*_spec.rb")))
            files.concat(Dir.glob(File.join(p, "**", "{spec,rails}_helper.rb")))
          elsif File.file?(p)
            files << p
          else
            warn "warning: path not found: #{p}"
          end
        end
        files.uniq
      end

      def log(msg = nil)
        msg = yield if block_given?
        puts msg
      end

      def analyze_paths(paths)
        files = find_files(paths)
        total = 0

        files.each do |file|
          rewriter = transpiled(file)
          next if rewriter.lints.empty?

          log { "File: #{file}" }
          rewriter.lints.each do |lint|
            log { format("  line %-4d %-8s [%s] %s", lint.line, lint.severity, lint.code, lint.message) }
            total += 1
          end
        end

        log { "Analysis complete. Total findings: #{total}" }
        true
      end

      def write_paths(paths)
        files = find_files(paths)
        count = 0

        files.each do |file|
          content = File.read(file)
          rewriter = Rewriter.new(content)
          new_code = rewriter.transpile

          next unless new_code != content

          if @diff
            print_diff(file, content, new_code)
          else
            File.write("#{file}.bak", content) if @backup
            File.write(file, new_code)
            log { "Transpiled: #{file}#{@backup ? " (backup: #{file}.bak)" : ""}" }
          end
          count += 1
        end

        log { @diff ? "Dry run complete. #{count} file(s) would change." : "Transpilation complete. Updated #{count} file(s)." }
        true
      end

      # Per-file concurrency-safety score plus the constructs that need
      # manual work, enabling incremental migration.
      def report_paths(paths)
        files = find_files(paths)
        rows = files.map do |file|
          rewriter = transpiled(file)
          manual = rewriter.lints.reject { |l| l.severity == :info }
          [file, rewriter.safety_score, rewriter.lints.size, manual]
        end

        log { format("%-60s %7s %9s", "File", "Score", "Findings") }
        log { "-" * 78 }
        rows.sort_by { |_, score, _, _| score }.each do |file, score, findings, manual|
          log { format("%-60s %6d%% %9d", file, score, findings) }
          manual.each do |lint|
            log { format("    line %-4d %-8s [%s] %s", lint.line, lint.severity, lint.code, lint.message) }
          end
        end

        avg = rows.empty? ? 100 : rows.sum { |_, s, _, _| s } / rows.size
        manual_total = rows.sum { |_, _, _, m| m.size }
        log { "-" * 78 }
        log { "#{rows.size} file(s), average safety score #{avg}%, #{manual_total} construct(s) need manual work." }
        true
      end

      def transpiled(file)
        rewriter = Rewriter.new(File.read(file))
        rewriter.transpile
        rewriter
      end

      def print_diff(file, old_code, new_code)
        log { "--- #{file}" }
        log { "+++ #{file} (transpiled)" }
        old_lines = old_code.lines
        new_lines = new_code.lines
        max = [old_lines.size, new_lines.size].max
        offset = 0
        old_lines.each_with_index do |line, i|
          new_line = new_lines[i + offset]
          next if line == new_line

          if new_lines[i + offset + 1] == line
            log { "+#{new_lines[i + offset]}" }
            offset += 1
            redo_line = new_lines[i + offset]
            log { " #{redo_line}" } if redo_line == line
          else
            log { "-#{line}" }
            log { "+#{new_line}" } if new_line
          end
        end
        (old_lines.size + offset...new_lines.size).each do |i|
          log { "+#{new_lines[i]}" }
        end
        max.zero? && nil
      end
    end
  end
end

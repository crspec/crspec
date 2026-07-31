# frozen_string_literal: true

require "json"
require "fileutils"

module Crspec
  # Persists per-example status and timing between runs. Backs
  # slowest-first scheduling and --only-failures. Keyed by the example's
  # stable identity (group description chain + example description).
  class StatusPersistence
    def initialize(path)
      @path = path
    end

    def load
      return {} unless @path && File.exist?(@path)

      JSON.parse(File.read(@path))
    rescue JSON::ParserError, Errno::ENOENT
      {}
    end

    def save(examples)
      return unless @path

      previous = load
      examples.each do |example|
        next if example.status == :pending

        previous[example.persistence_key] = {
          "status" => example.status.to_s,
          "run_time" => example.execution_time.round(6)
        }
      end

      dir = File.dirname(@path)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      tmp_path = File.join(dir, ".crspec-status-#{Process.pid}-#{rand(1_000_000)}")
      File.write(tmp_path, JSON.pretty_generate(previous))
      File.rename(tmp_path, @path)
    rescue SystemCallError
      File.delete(tmp_path) if tmp_path && File.exist?(tmp_path)
      nil
    end
  end
end

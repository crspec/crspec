# frozen_string_literal: true

require "pathname"

module Crspec
  module FileFixtures
    def file_fixture_path
      Crspec.configuration.file_fixture_path
    end

    def file_fixture(fixture_name)
      path = Pathname.new(File.join(file_fixture_path, fixture_name))
      return path if path.file?

      raise ArgumentError, "the directory '#{file_fixture_path}' does not contain a file named '#{fixture_name}'"
    end
  end
end

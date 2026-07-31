# frozen_string_literal: true

require_relative "lib/crspec/version"

Gem::Specification.new do |spec|
  spec.name = "crspec"
  spec.version = Crspec::VERSION
  spec.authors = ["Aboobacker MK"]
  spec.email = ["aboobackervyd@gmail.com"]

  spec.summary = "Concurrent, fiber-isolated Ruby testing framework ecosystem"
  spec.description = "Next-generation Ruby test runner using Fiber Storage isolation (Ruby 3.2+), fiber-aware mocks, connection leasing, and Prism AST transpilation."
  spec.homepage = "https://github.com/crspec/crspec"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  gemspec = File.basename(__FILE__)
  spec.files = if File.exist?(File.join(__dir__, ".git"))
                 IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
                   ls.read.split("\x0").reject do |f|
                     (f == gemspec) || f.start_with?(*%w[bin/ Gemfile .gitignore .github/ .rubocop.yml samples/ test/ benchmark/ demo.rb])
                   end
                 end
               else
                 Dir["{lib,exe}/**/*", "README.md", "LICENSE.txt"].select { |f| File.file?(f) }
               end

  spec.bindir = "exe"
  spec.executables = %w[crspec crspec-transpile]
  spec.require_paths = ["lib"]

  spec.add_dependency "async", ">= 2.0"
  spec.add_dependency "prism", ">= 0.19.0"
end

# frozen_string_literal: true

require_relative "crspec/version"
require_relative "crspec/execution_context"
require_relative "crspec/matchers"
require_relative "crspec/expectations"
require_relative "crspec/example"
require_relative "crspec/example_group"
require_relative "crspec/mock/interceptor"
require_relative "crspec/mock/space"
require_relative "crspec/mock/double"
require_relative "crspec/runner"
require_relative "crspec/dsl"
require_relative "crspec/rails/database_isolation"
require_relative "crspec/rails/system_server"
require_relative "crspec/rails/parallel"
require_relative "crspec/transpiler/rewriter"
require_relative "crspec/transpiler/cli"

module Crspec
  class Error < StandardError; end
end

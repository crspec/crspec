# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift File.expand_path(__dir__)

require "crspec"
require "rspec/core"
require "minitest"
require "stringio"

NUMBER_OF_TESTS = 100

Rails.logger.debug "=========================================================================="
Rails.logger.debug "  Crspec vs RSpec vs Minitest Benchmark Suite"
Rails.logger.debug { "  Test Workload: #{NUMBER_OF_TESTS} examples per framework" }
Rails.logger.debug "  Evaluating Default Native Framework Runners (No Manual Concurrency Controls)"
Rails.logger.debug "=========================================================================="

results = {}
null_formatter = Crspec::Formatters::NullFormatter.new

# -----------------------------------------------------------------------------
# 1. Crspec Native Execution (Default Concurrency Kernel)
# -----------------------------------------------------------------------------
Crspec.reset!
load File.expand_path("spec/user_service_crspec_spec.rb", __dir__)

t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
Crspec::Runner.new(formatter: null_formatter).run(Crspec.world.example_groups)
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
results["Crspec (Native Default Runner)"] = t1 - t0

# -----------------------------------------------------------------------------
# 2. RSpec Native Execution
# -----------------------------------------------------------------------------
config = RSpec::Core::Configuration.new
config.output_stream = StringIO.new
world = RSpec::Core::World.new(config)
RSpec.instance_variable_set(:@world, world)
load File.expand_path("spec/user_service_rspec_spec.rb", __dir__)

t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
world.example_groups.first.run(config.reporter)
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
results["RSpec (Native Default Runner)"] = t1 - t0

# -----------------------------------------------------------------------------
# 3. Minitest Native Execution
# -----------------------------------------------------------------------------
load File.expand_path("test/user_service_test.rb", __dir__)

t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
Minitest::CompositeReporter.new
UserServiceTest.runnable_methods.each do |method_name|
  UserServiceTest.new(method_name).run
end
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
results["Minitest (Native Default Runner)"] = t1 - t0

# -----------------------------------------------------------------------------
# Summary Output
# -----------------------------------------------------------------------------
Rails.logger.debug "\nResults Summary:"
Rails.logger.debug format("%-45s | %-12s | %-15s", "Framework Engine", "Duration (s)", "Throughput (ops/s)")
Rails.logger.debug "-" * 78

results.each do |engine, duration|
  throughput = (NUMBER_OF_TESTS / duration).round(2)
  Rails.logger.debug format("%-45s | %-12.4f | %-15.2f", engine, duration, throughput)
end

Rails.logger.debug "=" * 78

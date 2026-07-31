# frozen_string_literal: true

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "crspec", path: __dir__
  gem "prism"
end

require "crspec"

Rails.logger.debug "================================================================="
Rails.logger.debug "  Crspec Single-File Inline Demo & Feature Verification          "
Rails.logger.debug "================================================================="

# Reset global state for clean standalone run
Crspec.reset!

# Domain Models
class User
  attr_accessor :name, :email

  def initialize(name:, email:)
    @name = name
    @email = email
  end

  def valid?
    return false if name.nil? || email.nil?

    email.include?("@")
  end
end

class PaymentProcessor
  def charge(amount)
    "real_charge_#{amount}"
  end
end

# 1. Core DSL, Context Isolation, Lazy Let Memoization, Matchers
Crspec.describe User, type: :model do
  let(:valid_attributes) { { name: "Jane Doe", email: "jane@example.com" } }
  subject(:user) { User.new(**valid_attributes) }

  before do
    # Per-example setup hook
  end

  it "validates primary attributes concurrently" do
    expect(user.valid?).to be(true)
    expect(user.name).to eq("Jane Doe")
    expect(user.email).to include("example.com")
  end

  context "when email is invalid" do
    let(:valid_attributes) { { name: "Jane Doe", email: nil } }

    it "flags validation errors" do
      expect(user.valid?).to eq(false)
    end
  end

  context "when error is expected" do
    it "catches raised exceptions" do
      expect { raise ArgumentError, "Invalid user input" }.to raise_error(ArgumentError, "Invalid user input")
    end
  end
end

# 2. Fiber-Aware Mocking Engine (crspec-mock)
Crspec.describe PaymentProcessor do
  let(:processor) { PaymentProcessor.new }

  it "supports fiber-isolated method stubs" do
    allow(processor).to receive(:charge).with(5000).and_return("succeeded")
    expect(processor.charge(5000)).to eq("succeeded")
  end

  it "supports test doubles and method expectations" do
    gateway_double = double("StripeGateway", process: "ok")
    expect(gateway_double.process).to eq("ok")
  end
end

# 3. Rails Parallel Worker Integration (crspec-rails)
Crspec::Rails::Parallel.parallelize(workers: 4) do
  parallelize_setup do |worker_num|
    # Per-worker setup hook (e.g. database setup for worker_num)
  end

  parallelize_teardown do |worker_num|
    # Per-worker teardown hook
  end
end

# 4. Prism AST Transpiler Verification (crspec-transpiler)
rspec_sample_code = <<~RUBY
  RSpec.describe "Legacy Suite" do
    it "runs" do
      expect(1).to eq(1)
    end
  end
RUBY

transpiled = Crspec::Transpiler::Rewriter.new(rspec_sample_code).transpile
Rails.logger.debug do
  "[Prism Transpiler Check] RSpec -> Crspec: #{transpiled.include?("Crspec.describe") ? "PASSED" : "FAILED"}"
end

# 5. Concurrent Multi-Threaded Execution Kernel
Rails.logger.debug "\n[Executing Specs Concurrently Across 4 Worker Threads]..."
runner = Crspec::Runner.new(concurrency: 4)
runner.run(Crspec.world.example_groups)

Rails.logger.debug "\n---------------- Execution Summary ----------------"
Rails.logger.debug { "Total Duration : #{runner.total_duration.round(4)}s" }
Rails.logger.debug { "Passed Examples: #{runner.passed_examples.size}" }
Rails.logger.debug { "Failed Examples: #{runner.failed_examples.size}" }
Rails.logger.debug "---------------------------------------------------"

if runner.success?
  Rails.logger.debug "\nSUCCESS: All specs executed concurrently across 4 worker threads and passed cleanly!"
else
  Rails.logger.debug "\nFAILURE: Some specs failed."
  exit 1
end

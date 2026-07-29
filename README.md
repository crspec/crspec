# Crspec

**Crspec** is a next-generation concurrent, fiber-isolated Ruby testing framework ecosystem. By leveraging Ruby 3.2+ **Fiber Storage** (`Fiber[:key]`), fiber-aware method interceptors, non-blocking fiber schedulers, and `ruby/prism` AST transpilation, Crspec achieves ultra-fast concurrent test execution while maintaining full syntax compatibility with traditional RSpec suites.

---

## Key Features

- **Fiber Storage Context Isolation**: Solves legacy thread-local (`Thread.current`) state leakage by routing all execution metadata and `let` memoization through inherited Fiber storage (`Fiber[:crspec_execution_context]`).
- **Fiber-Aware Mocking (`crspec-mock`)**: Prevents mock registry corruption across parallel tests using prepended method interceptors bound to `Fiber[:crspec_mock_space]`.
- **Rails Connection Leasing & Parallel Testing (`crspec-rails`)**: Leases database connections per example fiber (`ActiveRecord::Base.lease_connection`), handles savepoint transaction strategies (`SAVEPOINT ex_root`), and integrates with Rails parallel worker suites (`Crspec::Rails::Parallel`).
- **Prism-Based AST Transpiler (`crspec-transpiler`)**: Automated migration tool using `ruby/prism` C-parser to convert existing RSpec codebases to Crspec syntax and flag thread-unsafe constructs like `before(:all)`.
- **Concurrent Execution Kernel**: Multi-threaded worker pool integrated with non-blocking fiber schedulers (`Async::Scheduler`).

---

## Installation

Add `crspec` to your application's `Gemfile`:

```ruby
gem "crspec", github: "crspec/crspec"
```

Then install via Bundler (or `mise`):

```bash
mise exec -- bundle install
```

---

## Writing Specs

`crspec` provides a familiar RSpec-style DSL for structuring example groups and expectations:

```ruby
require "crspec"

Crspec.describe User, type: :model do
  let(:valid_attributes) { { name: "Jane Doe", email: "jane@example.com" } }
  subject(:user) { User.new(valid_attributes) }

  before do
    Fiber[:trace_id] = "TX-#{SecureRandom.hex(4)}"
  end

  it "validates primary attributes" do
    expect(user.valid?).to be(true)
  end

  context "when email is omitted" do
    let(:valid_attributes) { { name: "Jane Doe", email: nil } }

    it "flags validation errors" do
      expect(user.valid?).to be(false)
      expect(user.errors[:email]).to include("can't be blank")
    end
  end
end
```

### Supported Matchers
- `eq(expected)`
- `be(expected)` / `be_nil` / `be_truthy` / `be_falsy`
- `include(*items)`
- `raise_error(ExceptionClass, "message")`
- `respond_to(*methods)`

---

## Fiber-Isolated Mocking (`crspec-mock`)

`crspec-mock` routes all doubles and stubs through `Fiber[:crspec_mock_space]`, allowing parallel tests to stub methods on shared target objects without cross-test pollution:

```ruby
Crspec.describe PaymentGateway do
  let(:stripe_client) { instance_double(Stripe::Charge) }

  it "stubs credit card processing concurrently" do
    allow(stripe_client).to receive(:create).with(amount: 5000).and_return(status: "succeeded")
    
    result = stripe_client.create(amount: 5000)
    expect(result[:status]).to eq("succeeded")
  end
end
```

---

## Rails Concurrency & Parallel Testing (`crspec-rails`)

### Database Isolation & Connection Leasing
Wrap examples in connection leasing and transaction savepoints:

```ruby
Crspec.describe User, type: :model do
  around do |example|
    Crspec::Rails::DatabaseIsolation.wrap_example(example)
  end
end
```

### Rails Parallel Testing Setup
Configure worker counts and setup/teardown hooks:

```ruby
Crspec::Rails::Parallel.parallelize(workers: 4) do
  parallelize_setup do |worker_number|
    # Prepare worker database, seed data, etc.
    puts "Worker #{worker_number} starting (TEST_ENV_NUMBER=#{ENV['TEST_ENV_NUMBER']})"
  end

  parallelize_teardown do |worker_number|
    puts "Worker #{worker_number} tearing down"
  end
end
```

### Multi-Fiber Integration Server
Boot an embedded multi-threaded/multi-fiber Puma server for system/browser specs:

```ruby
Crspec::Rails::SystemServer.start_concurrent_server!(Rails.application, 9887)
```

---

## Migrating from RSpec (`crspec-transpile`)

Use the built-in Prism-powered transpiler CLI to convert legacy RSpec suites to Crspec:

```bash
# 1. Analyze your test directory for thread-unsafe patterns (e.g. before(:all))
mise exec -- crspec-transpile --analyze spec/

# 2. Automatically transpile RSpec code to Crspec syntax in-place
mise exec -- crspec-transpile --write spec/
```

---

## Running Specs

Execute your test suite concurrently using the `crspec` executable:

```bash
# Run specs with default concurrency (number of CPU cores)
mise exec -- crspec spec/

# Run specs with specific concurrency
mise exec -- crspec -c 8 spec/models/
```

---

## Development & Testing

To run the internal framework unit tests (built with **Minitest**):

```bash
mise exec -- bundle exec rake test
```

---

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).

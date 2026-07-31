# Crspec Native Benchmark Suite

This directory contains benchmarking utilities comparing default native framework runner performance across **crspec**, **RSpec**, and **Minitest** without any manual thread-slicing or concurrency controls in the benchmark script.

---

## Directory Structure

```text
benchmark/
├── target_service.rb                        # Domain target class under test (UserService)
├── spec/
│   ├── user_service_crspec_spec.rb          # Idiomatic Crspec spec (Crspec.describe)
│   └── user_service_rspec_spec.rb           # Idiomatic RSpec spec (RSpec.describe)
├── test/
│   └── user_service_test.rb                 # Idiomatic Minitest test (class UserServiceTest < Minitest::Test)
├── run.rb                                   # Clean benchmark runner script
└── README.md
```

---

## Evaluated Configurations

Each framework is executed using its native default runner invocation:
- **Crspec (Native Default Runner)**: Uses `Crspec::Runner.new` default multi-threaded / fiber execution kernel.
- **RSpec (Native Default Runner)**: Native standard RSpec runner.
- **Minitest (Native Default Runner)**: Native Minitest runner.

---

## How to Run

```bash
mise exec -- ruby benchmark/run.rb
```

---

## Benchmark Results (macOS arm64 / Ruby 4.0.2)

```text
==========================================================================
  Crspec vs RSpec vs Minitest Benchmark Suite
  Test Workload: 100 examples per framework
  Evaluating Default Native Framework Runners (No Manual Concurrency Controls)
==========================================================================

Results Summary:
Framework Engine                              | Duration (s) | Throughput (ops/s)
------------------------------------------------------------------------------
Crspec (Native Default Runner)                | 0.0211       | 4749.47        
RSpec (Native Default Runner)                 | 0.1375       | 727.15         
Minitest (Native Default Runner)              | 0.1259       | 794.45         
==============================================================================
```

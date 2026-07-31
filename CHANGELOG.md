## [Unreleased]

### Added (Phases 2–5)

- **Fiber tier** (`--fibers M`, `config.fibers`): each worker thread runs up
  to M concurrent example-fibers on the Async reactor; IO-bound examples
  overlap within a thread. `async` is a soft dependency (add it to your
  Gemfile on CRuby); without it `--fibers` falls back to 1.
- **JRuby support**: full test suite passes on JRuby 10; threads scale
  across all cores (no GVL), so `-c N` is the multi-core tier there.
  `--processes N` raises with guidance (no fork); `--processes auto`
  gracefully falls back to threads.
- **Process tier** (`--processes P`, `--processes auto` = physical cores):
  forks after spec loading (`Process.warmup`), shards examples by persisted
  timings (LPT bin-packing, round-robin on first run), streams marshalled
  results over binary pipes, creates per-process `db_N` databases via
  `ActiveRecord::TestDatabases`, offsets `SystemServer` ports by
  `TEST_ENV_NUMBER`, and propagates fail-fast via SIGTERM.
- **Timing persistence** (`example_status_persistence_file_path`, CLI
  default `tmp/crspec_status.json`): slowest-first scheduling,
  `--only-failures`, and deterministic `--seed N` random ordering.
- **Real pending/skip**: `xit`, `skip`, `pending`, blockless `it`,
  `skip:`/`pending:` metadata, and `xdescribe`/`xcontext` no longer execute;
  reported as pending in the summary.
- **Verifying `instance_double`**: stubbing a method the doubled class does
  not implement raises `Crspec::Mock::MockError`; string class names are
  resolved.
- **Matchers**: `be_a`/`be_an`/`be_an_instance_of`/`be_falsey`, `match`,
  `match_array`/`contain_exactly`, `have_attributes`, `all`, `satisfy`,
  `be_within.of/.percent_of`, `start_with`/`end_with`,
  `output.to_stdout/.to_stderr`, `yield_control`/`yield_with_args`/
  `yield_successive_args`, compound `.and`/`.or`, custom-matcher DSL with
  `failure_message`/`failure_message_when_negated`/`description`/`chain`.
- **Mocks**: `spy` + `have_received` (with count/argument constraints),
  argument matchers (`anything`, `hash_including`, `hash_excluding`,
  `array_including`, `an_instance_of`, `kind_of`, `duck_type`),
  `and_call_original`, `receive_messages`.
- **Shared groups**: `shared_examples`/`shared_context`/`it_behaves_like`/
  `include_context`/`include_examples` (block re-registration; parallel-safe).
- **Filtering**: `--tag TAG[:VALUE]`, line-number filters (`spec.rb:42`),
  `fit`/`fdescribe`/`fcontext` focus, `aggregate_failures` backed by a
  fiber-local accumulator (`MultipleExpectationsNotMetError`).
- **Transpiler**: auto-rewrites `before(:all)`→`before(:each)` (annotated),
  `RSpec::Matchers.define`→`Crspec::Matchers.define`, focus aliases
  normalized; static thread-safety lints (class variables, constant
  mutation, `ENV[]=`, Timecop, `any_instance_of`) with severities;
  `--report` migration report with per-file safety scores; `--diff` dry-run
  and `.bak` backups; removed the dangerous `**/*.rb` fallback glob.

### Changed (breaking, pre-release)

- `before`/`after` with `:all`/`:context`/`:suite` scope raise
  `Crspec::MigrationError` at load time (also from `Crspec.configure`).
- `allow_any_instance_of`/`expect_any_instance_of` raise
  `Crspec::MigrationError` at runtime.
- Mock interceptor methods are removed after each run
  (`Mock::Interceptor.cleanup!`) instead of accumulating for the process
  lifetime.

### Changed (Phase 1 — concurrency kernel)

- **Removed `DatabaseIsolation::MUTEX`**, which serialized all transactional
  examples. Each worker now leases its own connection per writing pool
  (`lease_connection`, `pool.checkout` fallback) with a root non-joinable
  transaction; every example runs in a nested transaction (savepoint) rolled
  back afterwards. Fiber-Storage-keyed connection handoff makes fibers
  spawned inside an example see that example's connection. SQLite pools fall
  back to serialized per-example transactions (single-writer limitation).
  **Breaking:** the `pin_connection!` path was dropped.
- Runner queue rewritten: `Queue#close` + blocking pop replaces the racy
  `empty?`/`pop(true)`/`rescue` pattern; fail-fast drains the queue instead
  of using an abort flag.
- Result recording decontended: per-worker result arrays merged at join,
  formatter notifications outside any runner lock, buffered progress-dot
  output with periodic flush.
- Per-group example classes are built once per group/spec-type and cached
  (previously rebuilt for every example); all `ancestor_*` walks (hooks,
  lets, metadata, modules) are memoized and frozen via `ExampleGroup#finalize!`;
  `World` is frozen at the CLI boundary before the run starts.
- **Removed the `ENV["TEST_ENV_NUMBER"]` cross-thread race**: worker identity
  now lives in Fiber Storage (`Crspec::Rails::Parallel.current_worker_number`);
  ENV is never mutated from worker threads. Thread-scoped per-worker database
  switching (`db_N`) was removed — it returns at the process tier
  (`--processes`) where the convention is safe.

### Fixed

- POST/PUT/PATCH request helpers now send `Content-Type: application/json`
  for JSON bodies, so controllers parse params correctly.
- `Parallel.teardown_worker` uses `clear_active_connections!` instead of
  `clear_all_connections!`, which destroyed other workers' leased
  connections.

## [0.1.0] - 2026-07-29

- Initial release

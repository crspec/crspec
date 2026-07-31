# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class ConfigurationTest < Minitest::Test
  def setup
    Crspec.reset_configuration!
  end

  def teardown
    Crspec.reset_configuration!
  end

  def test_configuration_hooks_and_module_inclusion
    helper_module = Module.new do
      def custom_helper_method
        "helper_ok"
      end
    end

    before_called = false
    after_called = false

    Crspec.configure do |config|
      config.include(helper_module)
      config.before(:each) { before_called = true }
      config.after(:each) { after_called = true }
    end

    group = Crspec.describe "Configured Group" do
      it "uses included module and runs global hooks" do
        expect(custom_helper_method).to eq("helper_ok")
      end
    end

    runner = Crspec::Runner.new(concurrency: 1, formatter: Crspec::Formatters::NullFormatter.new)
    runner.run([group])

    assert runner.success?
    assert before_called
    assert after_called
  end

  def test_init_generator_in_non_rails_project_creates_only_spec_helper
    Dir.mktmpdir do |dir|
      spec_dir = File.join(dir, "spec")
      created = Crspec::Generators::Init.generate(spec_dir, dir)

      assert_equal 1, created.size
      assert File.exist?(File.join(spec_dir, "spec_helper.rb"))
      refute File.exist?(File.join(spec_dir, "rails_helper.rb"))

      spec_helper_content = File.read(File.join(spec_dir, "spec_helper.rb"))
      assert_includes spec_helper_content, "Crspec.configure"
    end
  end

  def test_init_generator_in_rails_project_creates_both_helpers
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config", "application.rb"), "# Rails app")

      spec_dir = File.join(dir, "spec")
      created = Crspec::Generators::Init.generate(spec_dir, dir)

      assert_equal 2, created.size
      assert File.exist?(File.join(spec_dir, "spec_helper.rb"))
      assert File.exist?(File.join(spec_dir, "rails_helper.rb"))

      rails_helper_content = File.read(File.join(spec_dir, "rails_helper.rb"))
      assert_includes rails_helper_content, "require_relative \"spec_helper\""
      assert_includes rails_helper_content, "DatabaseIsolation.wrap_example"
    end
  end
end

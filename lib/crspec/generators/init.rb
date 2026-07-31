# frozen_string_literal: true

require "fileutils"

module Crspec
  module Generators
    class Init
      SPEC_HELPER_CONTENT = <<~RUBY
        # frozen_string_literal: true

        require "crspec"
        require "etc"

        Crspec.configure do |config|
          config.concurrency = Etc.nprocessors

          config.before(:each) do
            # Setup hooks executed before every spec example
          end

          config.after(:each) do
            # Teardown hooks executed after every spec example
          end
        end
      RUBY

      RAILS_HELPER_CONTENT = <<~RUBY
        # frozen_string_literal: true

        require_relative "spec_helper"
        ENV["RAILS_ENV"] ||= "test"
        require File.expand_path("../config/environment", __dir__)

        # Prevent database truncation if environment is production
        abort("The Rails environment is running in production mode!") if defined?(Rails) && Rails.env.production?

        require "crspec"

        # Including support files for tests
        if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
          Rails.root.glob("spec/support/**/*.rb").each { |f| require f }
        end

        # Checks for pending migrations and applies them before tests are run.
        begin
          ActiveRecord::Migration.maintain_test_schema! if defined?(ActiveRecord::Migration)
        rescue ActiveRecord::PendingMigrationError => e
          abort e.to_s
        end

        Crspec.configure do |config|
          config.use_transactional_fixtures = true
          config.infer_spec_type_from_file_location!
          config.include(Crspec::Rails::RequestHelpers)

          config.around(:each) do |example|
            if defined?(ActiveRecord::Base) && config.use_transactional_fixtures
              Crspec::Rails::DatabaseIsolation.wrap_example(example)
            else
              example.execute!
            end
          end
        end
      RUBY

      def self.rails_project?(root_dir = Dir.pwd)
        File.exist?(File.join(root_dir, "bin/rails")) ||
          File.exist?(File.join(root_dir, "config/environment.rb")) ||
          File.exist?(File.join(root_dir, "config/application.rb"))
      end

      def self.generate(target_dir = "spec", root_dir = Dir.pwd)
        FileUtils.mkdir_p(target_dir)

        spec_helper_path = File.join(target_dir, "spec_helper.rb")
        rails_helper_path = File.join(target_dir, "rails_helper.rb")

        created = []

        unless File.exist?(spec_helper_path)
          File.write(spec_helper_path, SPEC_HELPER_CONTENT)
          created << spec_helper_path
        end

        if rails_project?(root_dir) && !File.exist?(rails_helper_path)
          File.write(rails_helper_path, RAILS_HELPER_CONTENT)
          created << rails_helper_path
        end

        created
      end
    end
  end
end

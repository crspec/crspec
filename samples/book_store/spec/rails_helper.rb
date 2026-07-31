# frozen_string_literal: true

require_relative "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require File.expand_path("../config/environment", __dir__) if File.exist?(File.expand_path("../config/environment.rb", __dir__))

# Prevent database truncation if environment is production
abort("The Rails environment is running in production mode!") if defined?(Rails) && Rails.env.production?

require "crspec"

# Checks for pending migrations and applies them before tests are run.
begin
  ActiveRecord::Migration.maintain_test_schema! if defined?(ActiveRecord::Migration)
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s
end

# Including support files for tests
if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
  Rails.root.glob("spec/support/**/*.rb").each { |f| require f }
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

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

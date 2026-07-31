#!/usr/bin/env ruby
# frozen_string_literal: true

begin
  if defined?(Rails) && Rails.env.test? && defined?(Warden::Manager)
    # Ensure there is always a failure app in test so that requests which
    # hit Warden::Manager#call_failure_app do not raise "No Failure App
    # provided" but instead respond with a simple 401/403 style response.
    Rails.application.config.middleware.insert_after Rack::Head, Warden::Manager do |config|
      config.failure_app ||= lambda do |_env|
        [401, { "Content-Type" => "text/plain" }, ["Unauthorized"]]
      end
    end unless Rails.application.config.middleware.any? { |m| m.klass == Warden::Manager }
  end
rescue StandardError
  # If the app doesn't use Warden/Devise in a conventional fashion we
  # silently skip installing the shim.
end

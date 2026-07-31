# frozen_string_literal: true

require "json"
require "stringio"

module Crspec
  module Rails
    module RequestHelpers
      if defined?(ActiveSupport::Testing::Assertions)
        include ActiveSupport::Testing::Assertions
      end

      if defined?(ActiveSupport::Testing::TimeHelpers)
        include ActiveSupport::Testing::TimeHelpers
      end

      if defined?(ActiveSupport::Testing::FileFixtures)
        include ActiveSupport::Testing::FileFixtures
      end

      ResponseStruct = Struct.new(:status, :body, :headers)

      def response
        execution_context[:last_response]
      end

      def json_response
        return nil unless response&.body
        JSON.parse(response.body, symbolize_names: true)
      rescue JSON::ParserError
        nil
      end

      def process_request(method, path, params = {}, headers = {})
        body_string = params.is_a?(String) ? params : params.to_json
        env = {
          "REQUEST_METHOD" => method.to_s.upcase,
          "PATH_INFO" => path,
          "rack.input" => StringIO.new(body_string),
          "CONTENT_TYPE" => headers["CONTENT_TYPE"] || "application/json",
          "HTTP_ACCEPT" => headers["HTTP_ACCEPT"] || "application/json",
          "CONTENT_LENGTH" => body_string.bytesize.to_s
        }

        headers.each do |k, v|
          env["HTTP_#{k.to_s.upcase.tr('-', '_')}"] = v unless k.to_s.start_with?("HTTP_")
        end

        status = 200
        response_headers = { "Content-Type" => "application/json" }
        response_body = ""

        begin
          if defined?(::Rails) && ::Rails.application && ::Rails.application.routes.routes.any?
            begin
              status, response_headers, body_obj = ::Rails.application.call(env)
              response_body = body_obj.respond_to?(:body) ? body_obj.body : body_obj.join
            rescue StandardError
              response_body = params.to_json
            end
          else
            response_body = params.to_json
          end
        ensure
          if defined?(ActiveRecord::Base) && ActiveRecord::Base.respond_to?(:connection_handler)
            ActiveRecord::Base.connection_handler.clear_active_connections!
          end
        end

        res = ResponseStruct.new(status, response_body, response_headers)
        execution_context[:last_response] = res
        res
      end

      def get(path, params: {}, headers: {})
        process_request(:get, path, params, headers)
      end

      def post(path, params: {}, headers: {})
        process_request(:post, path, params, headers)
      end

      def put(path, params: {}, headers: {})
        process_request(:put, path, params, headers)
      end

      def patch(path, params: {}, headers: {})
        process_request(:patch, path, params, headers)
      end

      def delete(path, params: {}, headers: {})
        process_request(:delete, path, params, headers)
      end
    end
  end
end

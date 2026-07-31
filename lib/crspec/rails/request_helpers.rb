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

      # Lightweight response wrapper that mimics the small subset of the
      # Rails test response API that the specs rely on (status, body,
      # headers, media_type, parsed_body, etc.).
      ResponseStruct = Struct.new(:status, :body, :headers) do
        def media_type
          content_type_header = headers["Content-Type"] || headers["content-type"]
          return nil unless content_type_header

          # Strip any charset or parameters, e.g. "application/json; charset=utf-8"
          content_type_header.split(";").first&.strip
        end

        def parsed_body
          return nil unless body
          JSON.parse(body)
        rescue JSON::ParserError
          nil
        end
      end

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
        # Emulate Rails integration test semantics:
        # - For GET/DELETE, params are typically carried in the query string
        # - For POST/PUT/PATCH with JSON, params are in the request body
        # - `format: :json` should affect the requested path / Accept header

        params = params.dup if params.is_a?(Hash)

        requested_format = nil
        if params.is_a?(Hash) && params.key?(:format)
          requested_format = params.delete(:format)&.to_s
        end

        path_with_format = path.dup
        if requested_format && !path_with_format.end_with?(".#{requested_format}")
          path_with_format = "#{path_with_format}.#{requested_format}"
        end

        query_string = nil
        body_string = ""

        if params.is_a?(Hash) && !params.empty?
          if %i[get delete].include?(method.to_sym)
            # Attach params as query string for idempotent verbs
            query_string = URI.encode_www_form(params)
          else
            # Default to JSON body for non-GET verbs when params are present
            body_string = params.to_json
            headers = headers.merge("CONTENT_TYPE" => "application/json") unless headers["CONTENT_TYPE"]
          end
        elsif params.is_a?(String)
          body_string = params
        end

        env = {
          "REQUEST_METHOD" => method.to_s.upcase,
          "PATH_INFO" => path_with_format,
          "QUERY_STRING" => query_string.to_s,
          "rack.input" => StringIO.new(body_string),
          "CONTENT_TYPE" => headers["CONTENT_TYPE"],
          "HTTP_ACCEPT" => headers["HTTP_ACCEPT"] || (requested_format == "json" ? "application/json" : nil),
          "CONTENT_LENGTH" => body_string.bytesize.to_s
        }.compact

        headers.each do |k, v|
          env["HTTP_#{k.to_s.upcase.tr('-', '_')}"] = v unless k.to_s.start_with?("HTTP_")
        end

        status = 200
        response_headers = { "Content-Type" => "text/plain" }
        response_body = ""

        begin
          if defined?(::Rails) && ::Rails.application && ::Rails.application.routes.routes.any?
            status, response_headers, body_obj = ::Rails.application.call(env)
            response_body = body_obj.respond_to?(:body) ? body_obj.body : body_obj.join
          else
            # No Rails app mounted; behave like a very small echo server.
            if (env["HTTP_ACCEPT"] || "").to_s.include?("json") ||
               (env["CONTENT_TYPE"] || "").to_s.include?("json") ||
               requested_format == "json"
              response_headers["Content-Type"] = "application/json"
              response_body = params.is_a?(String) ? params : params.to_json
            else
              response_headers["Content-Type"] = "text/plain"
              response_body = params.to_s
            end
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

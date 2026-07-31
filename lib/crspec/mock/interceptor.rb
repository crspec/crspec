# frozen_string_literal: true

module Crspec
  module Mock
    module Interceptor
      @intercepted_methods = {}
      @mutex = Mutex.new

      def method_missing(method_name, *args, **kwargs, &block)
        space = Fiber[Space::STORAGE_KEY]
        if space && (stub = space.fetch_stub(self, method_name))
          stub.call(*args, **kwargs, &block)
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        space = Fiber[Space::STORAGE_KEY]
        space&.fetch_stub(self, method_name) || super
      end

      class << self
        def add_intercept_method(method_name)
          method_sym = method_name.to_sym
          @mutex.synchronize do
            return if @intercepted_methods.key?(method_sym)
            return if instance_methods(false).include?(method_sym) ||
                      private_instance_methods(false).include?(method_sym)

            define_method(method_sym) do |*args, **kwargs, &block|
              space = Fiber[Space::STORAGE_KEY]
              if space && (stub = space.fetch_stub(self, method_sym))
                stub.call(*args, **kwargs, &block)
              else
                super(*args, **kwargs, &block)
              end
            end
            @intercepted_methods[method_sym] = true
          end
        end

        # Removes all dynamically-defined intercept methods so they do not
        # accumulate for the lifetime of the process (e.g. across multiple
        # embedded runner invocations). Stub lookups fall back to
        # method_missing until re-added.
        def cleanup!
          @mutex.synchronize do
            @intercepted_methods.each_key do |method_sym|
              remove_method(method_sym) if instance_methods(false).include?(method_sym)
            end
            @intercepted_methods.clear
          end
        end
      end
    end
  end
end

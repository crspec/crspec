# frozen_string_literal: true

module Crspec
  module Mock
    module Interceptor
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

      def self.add_intercept_method(method_name)
        method_sym = method_name.to_sym
        return if instance_methods(false).include?(method_sym) || private_instance_methods(false).include?(method_sym)

        define_method(method_sym) do |*args, **kwargs, &block|
          space = Fiber[Space::STORAGE_KEY]
          if space && (stub = space.fetch_stub(self, method_sym))
            stub.call(*args, **kwargs, &block)
          else
            super(*args, **kwargs, &block)
          end
        end
      end
    end
  end
end

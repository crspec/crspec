# frozen_string_literal: true

# In many Rails controller/request specs the asset pipeline is not the
# subject under test. When running under crspec, we provide a small shim
# around Sprockets helpers so that missing compiled assets do not cause
# hard failures.

module Crspec
  module Rails
    module AssetsShim
      module ComputeAssetPathFallback
        def compute_asset_path(path, options = {})
          super
        rescue StandardError
          path.to_s
        end
      end

      def self.install!
        return if @installed
        return unless defined?(::Rails) && ::Rails.env.test?
        return unless defined?(::Sprockets::Rails::Helper)

        ::Sprockets::Rails::Helper.prepend(ComputeAssetPathFallback)
        @installed = true
      rescue StandardError
        nil
      end
    end
  end
end

Crspec::Rails::AssetsShim.install!

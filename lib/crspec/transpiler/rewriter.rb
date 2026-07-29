# frozen_string_literal: true

require "prism"

module Crspec
  module Transpiler
    class Rewriter < Prism::Visitor
      attr_reader :transformed_code, :warnings

      def initialize(source_code)
        super()
        @source_code = source_code
        @replacements = []
        @warnings = []
      end

      def transpile
        result = Prism.parse(@source_code)
        result.value.accept(self)
        apply_replacements
      end

      def visit_call_node(node)
        # Convert RSpec.describe -> Crspec.describe
        if node.receiver.is_a?(Prism::ConstantReadNode) &&
           node.receiver.name == :RSpec &&
           node.name == :describe
          @replacements << {
            start_offset: node.receiver.location.start_offset,
            end_offset: node.receiver.location.end_offset,
            text: "Crspec"
          }
        end

        # Flag thread-unsafe before(:all) blocks
        if node.name == :before && node.arguments
          first_arg = node.arguments.arguments.first
          if first_arg.is_a?(Prism::SymbolNode) && first_arg.value == "all"
            @warnings << "Line #{node.location.start_line}: [Thread Safety Warning] before(:all) mutates global state across examples."
          end
        end

        super
      end

      def visit_constant_read_node(node)
        if node.name == :RSpec
          @replacements << {
            start_offset: node.location.start_offset,
            end_offset: node.location.end_offset,
            text: "Crspec"
          }
        end
        super
      end

      private

      def apply_replacements
        buffer = @source_code.dup
        # Sort replacements backwards so offsets remain valid during splicing
        sorted = @replacements.uniq { |r| [r[:start_offset], r[:end_offset]] }.sort_by { |r| -r[:start_offset] }
        sorted.each do |r|
          buffer[r[:start_offset]...r[:end_offset]] = r[:text]
        end
        @transformed_code = buffer
      end
    end
  end
end

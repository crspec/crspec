# frozen_string_literal: true

require "prism"

module Crspec
  module Transpiler
    # Lint severities:
    #   :error   - construct is rejected by Crspec at load/run time
    #   :warning - construct is concurrency-unsafe and needs manual review
    #   :info    - construct was auto-rewritten or is worth double-checking
    Lint = Struct.new(:line, :severity, :code, :message)

    class Rewriter < Prism::Visitor
      attr_reader :transformed_code, :warnings, :lints

      def initialize(source_code)
        super()
        @source_code = source_code
        @replacements = []
        @lints = []
        @inside_example_depth = 0
      end

      # Backwards-compatible string warnings.
      def warnings
        @lints.map { |l| "Line #{l.line}: [#{l.severity}] #{l.message}" }
      end

      def transpile
        result = Prism.parse(@source_code)
        result.value.accept(self)
        apply_replacements
      end

      def safety_score
        return 100 if @lints.empty?

        deductions = @lints.sum do |l|
          case l.severity
          when :error then 25
          when :warning then 10
          else 2
          end
        end
        [100 - deductions, 0].max
      end

      def visit_call_node(node)
        rewrite_rspec_receiver(node)
        rewrite_matcher_define(node)
        rewrite_before_all(node)
        rewrite_focus_aliases(node)
        lint_any_instance(node)
        lint_env_mutation(node)
        lint_time_mutation(node)

        example_call = %i[it specify example].include?(node.name)
        @inside_example_depth += 1 if example_call
        begin
          super
        ensure
          @inside_example_depth -= 1 if example_call
        end
      end

      def visit_constant_read_node(node)
        if node.name == :RSpec
          replace(node.location, "Crspec")
        end
        super
      end

      def visit_class_variable_write_node(node)
        add_lint(node, :warning, :class_variable,
                 "class variable mutation (#{node.name}) is shared across all threads/fibers")
        super
      end

      def visit_class_variable_read_node(node)
        add_lint(node, :warning, :class_variable,
                 "class variable read (#{node.name}) implies shared mutable state")
        super
      end

      def visit_constant_write_node(node)
        if @inside_example_depth.positive?
          add_lint(node, :warning, :constant_mutation,
                   "constant assignment (#{node.name}) inside an example mutates global state")
        end
        super
      end

      def visit_index_operator_write_node(node)
        lint_env_index(node)
        super
      end

      def visit_index_and_write_node(node)
        lint_env_index(node)
        super
      end

      def visit_index_or_write_node(node)
        lint_env_index(node)
        super
      end

      private

      def rewrite_rspec_receiver(node)
        return unless node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :RSpec

        replace(node.receiver.location, "Crspec")
      end

      # RSpec::Matchers.define -> Crspec::Matchers.define
      def rewrite_matcher_define(node)
        return unless node.name == :define
        return unless node.receiver.is_a?(Prism::ConstantPathNode)

        path = node.receiver
        parent = path.parent
        return unless parent.is_a?(Prism::ConstantReadNode) && parent.name == :RSpec && path.name == :Matchers

        replace(parent.location, "Crspec")
      end

      # before(:all)/before(:context) -> before(:each) with annotation.
      def rewrite_before_all(node)
        return unless %i[before after].include?(node.name) && node.arguments

        first_arg = node.arguments.arguments.first
        return unless first_arg.is_a?(Prism::SymbolNode) && %w[all context suite].include?(first_arg.value)

        add_lint(node, :info, :before_all_rewritten,
                 "#{node.name}(:#{first_arg.value}) auto-rewritten to #{node.name}(:each); " \
                 "review for per-example cost (consider let/let!)")
        replace(first_arg.location, ":each")
        annotate_line(node, "# CRSPEC-MIGRATION: was #{node.name}(:#{first_arg.value}) — now runs per example; consider let/let! for expensive setup")
      end

      # fit/fdescribe/fcontext are focus aliases; xit etc are already
      # supported natively. Normalize focus to plain forms with a note.
      def rewrite_focus_aliases(node)
        mapping = { fit: "it", fdescribe: "describe", fcontext: "context" }
        replacement = mapping[node.name]
        return unless replacement
        return if node.receiver

        add_lint(node, :info, :focus_removed,
                 "#{node.name} (focus) normalized to #{replacement}")
        replace(node.message_loc, replacement)
      end

      def lint_any_instance(node)
        if %i[any_instance allow_any_instance_of expect_any_instance_of].include?(node.name)
          add_lint(node, :error, :any_instance,
                   "#{node.name} mutates shared class hierarchies at runtime and is rejected by Crspec; " \
                   "inject a double or stub the specific instance instead")
        end
      end

      def lint_env_mutation(node)
        return unless node.name == :[]= && node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :ENV

        add_lint(node, :warning, :env_mutation,
                 "ENV mutation inside specs is process-global and races across threads")
      end

      def lint_env_index(node)
        return unless node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :ENV

        add_lint(node, :warning, :env_mutation,
                 "ENV mutation inside specs is process-global and races across threads")
      end

      TIME_MUTATORS = %i[travel travel_to travel_back freeze return].freeze

      def lint_time_mutation(node)
        receiver = node.receiver
        if receiver.is_a?(Prism::ConstantReadNode) && receiver.name == :Timecop
          add_lint(node, :warning, :time_mutation,
                   "Timecop.#{node.name} mutates global time state; use ActiveSupport::Testing::TimeHelpers " \
                   "scoped per example, or inject a clock")
        end
      end

      def add_lint(node, severity, code, message)
        @lints << Lint.new(node.location.start_line, severity, code, message)
      end

      def replace(location, text)
        @replacements << {
          start_offset: location.start_offset,
          end_offset: location.end_offset,
          text: text
        }
      end

      # Insert a comment line above the node's line.
      def annotate_line(node, comment)
        line_start = @source_code.rindex("\n", node.location.start_offset)
        line_start = line_start.nil? ? 0 : line_start + 1
        indent = @source_code[line_start..node.location.start_offset][/\A[ \t]*/]
        @replacements << {
          start_offset: line_start,
          end_offset: line_start,
          text: "#{indent}#{comment}\n"
        }
      end

      def apply_replacements
        buffer = @source_code.dup
        # Sort replacements backwards so offsets remain valid during splicing
        sorted = @replacements.uniq { |r| [r[:start_offset], r[:end_offset], r[:text]] }
                              .sort_by { |r| [-r[:start_offset], -r[:end_offset]] }
        sorted.each do |r|
          buffer[r[:start_offset]...r[:end_offset]] = r[:text]
        end
        @transformed_code = buffer
      end
    end
  end
end

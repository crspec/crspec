# frozen_string_literal: true

require "test_helper"

class TranspilerTest < Minitest::Test
  def test_prism_ast_rewriting_rspec_to_crspec
    source = <<~RUBY
      RSpec.describe User, type: :model do
        let(:valid_attributes) { { name: "Jane" } }
        it "validates attributes" do
          expect(1).to eq(1)
        end
      end
    RUBY

    rewriter = Crspec::Transpiler::Rewriter.new(source)
    transformed = rewriter.transpile

    assert_includes transformed, "Crspec.describe User"
    refute_includes transformed, "RSpec.describe"
  end

  def test_detects_thread_unsafe_before_all
    source = <<~RUBY
      Crspec.describe Account do
        before(:all) do
          @account = Account.create!
        end
        it "tests something" do
          expect(1).to eq(1)
        end
      end
    RUBY

    rewriter = Crspec::Transpiler::Rewriter.new(source)
    rewriter.transpile

    refute_empty rewriter.warnings
    assert_includes rewriter.warnings.first, "before(:all) mutates global state"
  end
end

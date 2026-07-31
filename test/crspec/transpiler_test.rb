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

  def test_rewrites_thread_unsafe_before_all
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
    transformed = rewriter.transpile

    refute_empty rewriter.warnings
    assert_includes transformed, "before(:each)"
    refute_match(/^\s*before\(:all\)/, transformed)
    assert_includes transformed, "# CRSPEC-MIGRATION: was before(:all)"
    assert_equal :info, rewriter.lints.first.severity
  end

  def test_rewrites_matcher_define_and_focus
    source = <<~RUBY
      RSpec::Matchers.define :be_valid do
        match { |actual| actual.valid? }
      end

      RSpec.describe Thing do
        fit "focused example" do
          expect(1).to eq(1)
        end
        fdescribe "focused group" do
        end
      end
    RUBY

    transformed = Crspec::Transpiler::Rewriter.new(source).transpile

    assert_includes transformed, "Crspec::Matchers.define"
    refute_includes transformed, "RSpec::Matchers"
    assert_match(/^  it "focused example"/, transformed)
    assert_includes transformed, "describe \"focused group\""
    refute_includes transformed, "fit "
    refute_includes transformed, "fdescribe"
  end

  def test_lints_thread_unsafety
    source = <<~RUBY
      Crspec.describe Danger do
        it "mutates stuff" do
          @@counter = 1
          ENV["MODE"] = "test"
          Timecop.freeze(Time.now)
          allow_any_instance_of(User).to receive(:save)
        end
      end
    RUBY

    rewriter = Crspec::Transpiler::Rewriter.new(source)
    rewriter.transpile
    codes = rewriter.lints.map(&:code)

    assert_includes codes, :class_variable
    assert_includes codes, :env_mutation
    assert_includes codes, :time_mutation
    assert_includes codes, :any_instance
    assert_equal :error, rewriter.lints.find { |l| l.code == :any_instance }.severity
    assert_operator rewriter.safety_score, :<, 100
  end

  def test_safety_score_clean_file
    source = <<~RUBY
      Crspec.describe Clean do
        it "is fine" do
          expect(1).to eq(1)
        end
      end
    RUBY

    rewriter = Crspec::Transpiler::Rewriter.new(source)
    rewriter.transpile

    assert_equal 100, rewriter.safety_score
    assert_empty rewriter.lints
  end
end

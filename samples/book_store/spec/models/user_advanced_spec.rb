# frozen_string_literal: true

require_relative "../rails_helper"
require "securerandom"

Crspec.describe "Advanced User Capabilities", type: :model do
  let!(:eager_user) { User.create!(name: "Eager User", email: "eager_#{SecureRandom.hex(4)}@example.com") }

  before do
    execution_context[:request_id] = "REQ-99"
  end

  it "evaluates eager let! before example execution" do
    expect(eager_user.name).to eq("Eager User")
  end

  it "accesses fiber-isolated execution context" do
    expect(execution_context[:request_id]).to eq("REQ-99")
  end

  it "validates message expectations with once count" do
    notifier = double("UserNotifier")
    expect(notifier).to receive(:send_welcome).once

    notifier.send_welcome
  end
end

# frozen_string_literal: true

require_relative "../rails_helper"
require "active_support/testing/time_helpers"

class DiscountCalculator
  def self.active_discount?
    Time.now.month == 12
  end
end

Crspec.describe DiscountCalculator do
  include ActiveSupport::Testing::TimeHelpers

  it "validates holiday discount in December" do
    travel_to Time.zone.parse("2026-12-25 10:00:00") do
      expect(DiscountCalculator.active_discount?).to be(true)
    end
  end

  it "validates no holiday discount in July" do
    travel_to Time.zone.parse("2026-07-15 10:00:00") do
      expect(DiscountCalculator.active_discount?).to be(false)
    end
  end
end

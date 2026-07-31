# frozen_string_literal: true

require_relative "../spec_helper"

class InventoryService
  def self.check_stock(book_id, client)
    response = client.fetch_stock(book_id)
    response[:in_stock] ? "In Stock (#{response[:quantity]} copies)" : "Out of Stock"
  end
end

Crspec.describe InventoryService do
  let(:client_double) { instance_double("StockClient") }

  it "returns in-stock messaging using fiber-isolated doubles" do
    allow(client_double).to receive(:fetch_stock).with(101).and_return(in_stock: true, quantity: 5)

    result = InventoryService.check_stock(101, client_double)
    expect(result).to eq("In Stock (5 copies)")
  end

  it "returns out-of-stock messaging" do
    allow(client_double).to receive(:fetch_stock).with(202).and_return(in_stock: false, quantity: 0)

    result = InventoryService.check_stock(202, client_double)
    expect(result).to eq("Out of Stock")
  end
end

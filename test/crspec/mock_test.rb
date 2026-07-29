# frozen_string_literal: true

require "test_helper"

class MockTest < Minitest::Test
  class StripeClient
    def charge(amount)
      "real_charge_#{amount}"
    end
  end

  def test_fiber_isolated_stubs
    client = StripeClient.new
    fiber1_result = nil
    fiber2_result = nil

    f1 = Fiber.new do
      Crspec::Mock::Space.current.register_stub(client, :charge, proc { "stub_fiber_1" })
      fiber1_result = client.charge(100)
    end

    f2 = Fiber.new do
      Crspec::Mock::Space.current.register_stub(client, :charge, proc { "stub_fiber_2" })
      fiber2_result = client.charge(200)
    end

    f1.resume
    f2.resume

    assert_equal "stub_fiber_1", fiber1_result
    assert_equal "stub_fiber_2", fiber2_result
    assert_equal "real_charge_500", client.charge(500)
  end

  def test_double_and_expectation_dsl
    Crspec::ExecutionContext.isolate("mock-test") do
      stubs_mock = Crspec::Mock::Double.new("Stripe", charge: "ok")
      assert_equal "ok", stubs_mock.charge(50)
    end
  end

  def test_allow_receive_with_and_return
    group = Crspec.describe "PaymentGateway" do
      it "stubs method" do
        client = StripeClient.new
        allow(client).to receive(:charge).with(5000).and_return("succeeded")
        expect(client.charge(5000)).to eq("succeeded")
      end
    end

    runner = Crspec::Runner.new(concurrency: 1)
    runner.run([group])
    assert runner.success?
  end
end

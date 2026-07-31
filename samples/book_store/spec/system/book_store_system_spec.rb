# frozen_string_literal: true

require_relative "../rails_helper"
require "net/http"

Crspec.describe "BookStore System Server", type: :system do
  it "boots Puma server and handles HTTP requests" do
    app = ->(_env) { [ 200, { "Content-Type" => "text/html" }, [ "<h1>Welcome to BookStore</h1>" ] ] }
    Crspec::Rails::SystemServer.start_concurrent_server!(app, 9889)

    expect(Crspec::Rails::SystemServer.running?).to be(true)

    port = Crspec::Rails::SystemServer.effective_port(9889)
    uri = URI("http://127.0.0.1:#{port}/")
    res = Net::HTTP.get_response(uri)
    expect(res.code).to eq("200")
    expect(res.body).to include("Welcome to BookStore")
  end
end

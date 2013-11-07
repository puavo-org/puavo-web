require_relative "./helper"
require_relative "../lib/fluent"

describe PuavoRest::FluentRelay do

  before(:each) do
    @orig_logger = FLUENT_RELAY
    PuavoRest::FluentRelay.fluent_logger = MockFluent.new
  end

  after(:each) do
    PuavoRest::FluentRelay.fluent_logger = nil
  end

  it "can relay log data to fluentd" do
    post "/v3/fluent/testtag1", {
      "foo" => 1,
      "bar" => 2
    }.to_json, "CONTENT_TYPE" => "application/json"
    assert_200

    data = PuavoRest::FluentRelay.fluent_logger.data
    assert_equal(
      [["testtag1", {"foo"=>1, "bar"=>2}]],
      data
    )
  end

  it "can relay multiple records at once" do
    post(
      "/v3/fluent/testtag2",
      [ { "foo" => 3 }, { "bar" => 4 } ].to_json,
      "CONTENT_TYPE" => "application/json"
    )
    assert_200

    data = PuavoRest::FluentRelay.fluent_logger.data
    assert_equal(
      [
        ["testtag2", {"foo"=>3}],
        ["testtag2", {"bar"=>4}]
      ],
      data
    )
  end

  it "responds non 200 if fluent post failed" do
    PuavoRest::FluentRelay.fluent_logger = MockFluent.new :broken => true
    post "/v3/fluent/testtag1", {
      "foo" => 1,
      "bar" => 2
    }.to_json, "CONTENT_TYPE" => "application/json"
    assert_equal 500, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal "Failed to relay fluent packages", data["error"]["message"]
  end

end

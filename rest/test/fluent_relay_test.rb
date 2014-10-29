require_relative "./helper"
require_relative "../lib/fluent"

describe PuavoRest::FluentRelay do

  before(:each) do
    Puavo::Test.clean_up_ldap
    create_basic_data
    PuavoRest::FluentRelay.fluent_logger = MockFluent.new
  end

  after(:each) do
    PuavoRest::FluentRelay.fluent_logger = nil
  end

  it "can relay log data to fluentd" do
    basic_authorize @laptop.dn, @laptop.ldap_password
    time = Time.now.to_i
    post "/v3/fluent", {
      "_tag" => "testtag1",
      "_time" => time,
      "foo" => 1,
      "bar" => 2
    }.to_json, "CONTENT_TYPE" => "application/json"
    assert_200

    data = PuavoRest::FluentRelay.fluent_logger.timed_data
    assert_equal(
      [["testtag1",  {"foo"=>1, "bar"=>2}, time]],
      data
    )
  end

  it "can relay msgpack log data to fluentd" do
    basic_authorize @laptop.dn, @laptop.ldap_password
    time = Time.now.to_i

    post "/v3/fluent", [
      "testtag1",
      time,
      { "foo" => 1, "bar" => 2 }
    ].to_msgpack, "CONTENT_TYPE" => "application/x-msgpack"

    assert_200

    data = PuavoRest::FluentRelay.fluent_logger.timed_data
    assert_equal(
      [["testtag1",  {"foo"=>1, "bar"=>2}, time]],
      data
    )
  end

  it "can relay multiple msgpack records at once" do
    basic_authorize @laptop.dn, @laptop.ldap_password
    time1 = Time.now.to_i - 10
    time2 = Time.now.to_i

    body = [ "tag1", time1, {"foo" => 1} ].to_msgpack
    body += [ "tag2", time2, {"foo" => 3} ].to_msgpack

    post "/v3/fluent", body, "CONTENT_TYPE" => "application/x-msgpack"
    assert_200

    data = PuavoRest::FluentRelay.fluent_logger.timed_data
    assert_equal([
        [ "tag1", {"foo" => 1}, time1],
        [ "tag2", {"foo" => 3}, time2],
    ],
      data
    )
  end

  it "can relay multiple records at once" do
    basic_authorize @laptop.dn, @laptop.ldap_password
    time1 = Time.now.to_i - 10
    time2 = Time.now.to_i
    post("/v3/fluent", [
        {
          "_tag" => "tag1",
          "_time" => time1,
          "foo" => 1
        },
        {
          "_tag" => "tag2",
          "_time" => time2,
          "foo" => 3
        }
    ].to_json,
      "CONTENT_TYPE" => "application/json"
    )
    assert_200

    data = PuavoRest::FluentRelay.fluent_logger.timed_data
    assert_equal([
        [ "tag1", {"foo" => 1}, time1],
        [ "tag2", {"foo" => 3}, time2],
    ],
      data
    )
  end

  it "responds non 200 if fluent post failed" do
    PuavoRest::FluentRelay.fluent_logger = MockFluent.new :broken => true
    basic_authorize @laptop.dn, @laptop.ldap_password
    time = Time.now.to_i
    post "/v3/fluent", {
      "_tag" => "testtag1",
      "_time" => time,
      "foo" => 1,
      "bar" => 2
    }.to_json, "CONTENT_TYPE" => "application/json"
    assert_equal 500, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal "Failed to relay fluent packages", data["error"]["message"]
  end

end

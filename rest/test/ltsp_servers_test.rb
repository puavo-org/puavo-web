require "fileutils"
require_relative "./helper"

describe PuavoRest::LtspServers do


  before(:each) do
    Puavo::Test.clean_up_ldap
    FileUtils.rm_rf PuavoRest::CONFIG["ltsp_server_data_dir"]

    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor"
    )
  end

  it "responds with empty data" do
    get "/v3/ltsp_servers"
    assert_equal "[]", last_response.body
  end

  it "responds 400 for unknown servers" do
    put "/v3/ltsp_servers/unknownserver",
      "load_avg" => "1.0",
      "cpu_count" => 1

    assert_equal 400, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal(
      "cannot find server from LDAP for hostname unknownserver",
      data["message"]
    )
  end

  it "can set load average" do
    create_server(
      :puavoHostname => "testserver",
      :macAddress => "bc:5f:f4:56:59:71"
    )

    put "/v3/ltsp_servers/testserver", "load_avg" => "1.0"
    get "/v3/ltsp_servers/testserver"
    data = JSON.parse(last_response.body)
    assert_equal 200, last_response.status
    assert_in_delta 1.0, data["state"]["load_avg"], 0.01
  end

  it "respond 400 to 0 cpu_count" do
    create_server(
      :puavoHostname => "testserver",
      :macAddress => "bc:5f:f4:56:59:71"
    )

    put "/v3/ltsp_servers/testserver", "load_avg" => "3.13", "cpu_count" => "0"
    data = JSON.parse(last_response.body)
    assert_equal 400, last_response.status
    assert_equal(
      {"message"=>"0 cpu_count makes no sense"},
      data
    )

  end

  it "can set load average with cpu_count" do
    create_server(
      :puavoHostname => "testserver",
      :macAddress => "bc:5f:f4:56:59:71"
    )

    put "/v3/ltsp_servers/testserver", "load_avg" => "1.0", "cpu_count" => 2
    get "/v3/ltsp_servers/testserver"
    data = JSON.parse(last_response.body)
    assert_in_delta 0.5, data["state"]["load_avg"], 0.01
  end

  it "can will contain school data if set" do
    create_server(
      :puavoHostname => "testserver",
      :macAddress => "bc:5f:f4:56:59:71",
      :puavoSchool => @school.dn
    )

    put "/v3/ltsp_servers/testserver", "load_avg" => "1.0", "cpu_count" => 2
    get "/v3/ltsp_servers/testserver"
    data = JSON.parse(last_response.body)
    assert_equal @school.dn, data["schools"].first
  end

  it "can return only the most idle sever" do
    create_server(
      :puavoHostname => "testserver",
      :macAddress => "bc:5f:f4:56:59:71"
    )
    create_server(
      :puavoHostname => "idleserver",
      :macAddress => "bc:5f:f4:56:59:72"
    )

    put "/v3/ltsp_servers/testserver", "load_avg" => "1.0", "cpu_count" => 2
    put "/v3/ltsp_servers/idleserver", "load_avg" => "0.2", "cpu_count" => 2

    get "/v3/ltsp_servers/_most_idle"
    data = JSON.parse(last_response.body)
    assert_equal "idleserver", data["hostname"]
  end

end

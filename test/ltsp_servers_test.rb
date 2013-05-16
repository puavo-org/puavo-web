require "fileutils"
require "./test/helper"

describe PuavoRest::LtspServers do

  before(:each) do
    FileUtils.rm_rf PuavoRest::CONFIG["ltsp_server_data_dir"]
  end

  it "responds with empty data" do
    get "/v3/ltsp_servers"
    assert_equal last_response.body, "[]"
  end

  it "can set load average" do
    put "/v3/ltsp_servers/testserver", "load_avg" => "1.0"
    get "/v3/ltsp_servers/testserver"
    data = JSON.parse(last_response.body)
    assert_in_delta 1.0, data["load_avg"], 0.01
  end

  it "can set load average with cpu_count" do
    put "/v3/ltsp_servers/testserver", "load_avg" => "1.0", "cpu_count" => 2
    get "/v3/ltsp_servers/testserver"
    data = JSON.parse(last_response.body)
    assert_in_delta 0.5, data["load_avg"], 0.01
  end

  it "can return only the most idle sever" do
    put "/v3/ltsp_servers/testserver", "load_avg" => "1.0", "cpu_count" => 2
    put "/v3/ltsp_servers/idleserver", "load_avg" => "0.2", "cpu_count" => 2

    get "/v3/ltsp_servers/_most_idle"
    data = JSON.parse(last_response.body)
    assert_equal "idleserver", data["domain"]
  end

end

require_relative "./helper"

describe PuavoRest::Devices do

  before(:each) do
    Puavo::Test.clean_up_ldap
    FileUtils.rm_rf PuavoRest::CONFIG["ltsp_server_data_dir"]
    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor",
      :puavoDeviceImage => "schoolprefimage"
    )
    @server1 = create_server(
      :puavoHostname => "server1",
      :macAddress => "bc:5f:f4:56:59:71"
    )
    @server2 = create_server(
      :puavoHostname => "server2",
      :macAddress => "bc:5f:f4:56:59:72"
    )
  end

  describe "device infromation without fallback" do
    before(:each) do
      create_device(
        :puavoHostname => "athin",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoPreferredServer => @server1.dn,
        :puavoDeviceImage => "customimage",
        :puavoSchool => @school.dn
      )
      get "/v3/devices/athin"
      assert_200
      @data = JSON.parse last_response.body
    end

    it "has mac address" do
      assert_equal "bf:9a:8c:1b:e0:6a", @data["mac_address"]
    end

    it "has preferred server" do
      assert_equal @server1.dn, @data["preferred_server"]
    end

    it "has preferred image" do
      assert_equal "customimage", @data["preferred_image"]
    end
  end

  describe "device with school fallback" do

    before(:each) do
      create_device(
        :puavoHostname => "athin",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school.dn
      )
    end

    it "has school preferred image when fallback_defaults=1 is set" do
      get "/v3/devices/athin?fallback_defaults=1"
      assert_200
      @data = JSON.parse last_response.body
      assert_equal "schoolprefimage", @data["preferred_image"]
    end

    it "is not in use unless fallback_defaults=1 is defined" do
      get "/v3/devices/athin"
      assert_200
      @data = JSON.parse last_response.body
      assert_equal nil, @data["preferred_image"]
    end

  end


end

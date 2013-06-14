require_relative "./helper"

describe PuavoRest::Devices do

  before(:each) do
    Puavo::Test.clean_up_ldap
    FileUtils.rm_rf PuavoRest::CONFIG["ltsp_server_data_dir"]
    @school1 = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor"
    )
    @school2 = School.create(
      :cn => "gryffindor2",
      :displayName => "Gryffindor2",
      :puavoDeviceImage => "schoolprefimage",
      :puavoPersonalDevice => true,
      :puavoAllowGuest => true
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

  describe "device infromation" do
    before(:each) do
      create_device(
        :puavoHostname => "athin",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoPreferredServer => @server1.dn,
        :puavoDeviceImage => "customimage",
        :puavoSchool => @school1.dn,
        :puavoPersonalDevice => false,
        :puavoAllowGuest => false
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

    it "has allow guest" do
      assert_equal "FALSE", @data["allow_guest"]
    end

    it "has personal device" do
      assert_equal "FALSE", @data["personal_device"]
    end
  end

  describe "device information with school fallback" do

    before(:each) do
      create_device(
        :puavoHostname => "athin",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school2.dn
      )
      get "/v3/devices/athin"
      assert_200
      @data = JSON.parse last_response.body
    end

    it "has preferred image" do
      assert_equal "schoolprefimage", @data["preferred_image"]
    end

    it "has allow guest" do
      assert_equal "TRUE", @data["allow_guest"]
    end

    it "has personal device" do
      assert_equal "TRUE", @data["personal_device"]
    end
  end

  describe "device information with organisation fallback" do

    before(:each) do
      create_device(
        :puavoHostname => "athin",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school1.dn
      )
      test_organisation = LdapOrganisation.first
      test_organisation.puavoAllowGuest = "FALSE"
      test_organisation.puavoPersonalDevice = "FALSE"
      test_organisation.save!
      get "/v3/devices/athin"
      assert_200
      @data = JSON.parse last_response.body
    end

    it "has allow guest" do
      assert_equal "FALSE", @data["allow_guest"]
    end

    it "has personal device" do
      assert_equal "FALSE", @data["personal_device"]
    end
  end
end

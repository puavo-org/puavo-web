require_relative "./helper"

describe PuavoRest::Devices do

  before(:each) do
    Puavo::Test.clean_up_ldap
    FileUtils.rm_rf PuavoRest::CONFIG["ltsp_server_data_dir"]
    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor",
      :puavoDeviceImage => "schoolprefimage",
      :puavoPersonalDevice => true,
      :puavoAllowGuest => true
    )
    @school_without_fallback_value = School.create(
      :cn => "gryffindor2",
      :displayName => "Gryffindor2"
    )
    @server1 = create_server(
      :puavoHostname => "server1",
      :macAddress => "bc:5f:f4:56:59:71"
    )
    @server2 = create_server(
      :puavoHostname => "server2",
      :macAddress => "bc:5f:f4:56:59:72"
    )
    test_organisation = LdapOrganisation.first # TODO: fetch by name
    test_organisation.puavoAllowGuest = "FALSE"
    test_organisation.puavoPersonalDevice = "FALSE"
    test_organisation.save!
  end

  describe "device infromation" do
    before(:each) do
      create_device(
        :puavoHostname => "athin",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoPreferredServer => @server1.dn,
        :puavoDeviceImage => "customimage",
        :puavoSchool => @school.dn,
        :puavoPersonalDevice => false,
        :puavoAllowGuest => false,
        :puavoPrinterDeviceURI => "usb:/dev/usb/lp1"
      )
      test_organisation = LdapOrganisation.first # TODO: fetch by name
      test_organisation.puavoAllowGuest = "TRUE"
      test_organisation.puavoPersonalDevice = "TRUE"
      test_organisation.save!
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
      assert_equal false, @data["allow_guest"]
    end

    it "has personal device" do
      assert_equal false, @data["personal_device"]
    end

    it "has printer uri" do
      assert_equal "usb:/dev/usb/lp1", @data["printer_device_uri"]
    end
  end

  describe "device information with school fallback" do

    before(:each) do
      create_device(
        :puavoHostname => "athin",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school.dn
      )
      get "/v3/devices/athin"
      assert_200
      @data = JSON.parse last_response.body
    end

    it "has preferred image" do
      assert_equal "schoolprefimage", @data["preferred_image"]
    end

    it "has allow guest" do
      assert_equal true, @data["allow_guest"]
    end

    it "has personal device" do
      assert_equal true, @data["personal_device"]
    end
  end

  describe "device information with organisation fallback" do

    before(:each) do
      create_device(
        :puavoHostname => "athin",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school_without_fallback_value.dn
      )
      get "/v3/devices/athin"
      assert_200
      @data = JSON.parse last_response.body
    end

    it "has allow guest" do
      assert_equal false, @data["allow_guest"]
    end

    it "has personal device" do
      assert_equal false, @data["personal_device"]
    end
  end

  describe "device information with global default" do
    before(:each) do
      create_device(
        :puavoHostname => "athin",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school_without_fallback_value.dn
      )
      test_organisation = LdapOrganisation.first # TODO: fetch by name
      test_organisation.puavoAllowGuest = nil
      test_organisation.puavoPersonalDevice = nil
      test_organisation.save!
      get "/v3/devices/athin"
      assert_200
      @data = JSON.parse last_response.body
    end

    it "has allow guest" do
      assert_equal false, @data["allow_guest"]
    end

    it "has personal device" do
      assert_equal false, @data["personal_device"]
    end
  end

  describe "error handling" do
    it "responds 404 for non existent device" do
      get "/v3/devices/notexists"
      assert_equal 404, last_response.status
      data = JSON.parse last_response.body
      assert_equal "NotFound", data["error"]["code"], data
    end

  end
end

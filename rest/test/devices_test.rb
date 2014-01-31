require_relative "./helper"

describe PuavoRest::Devices do

  before(:each) do
    Puavo::Test.clean_up_ldap
    FileUtils.rm_rf CONFIG["ltsp_server_data_dir"]
    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor",
      :puavoDeviceImage => "schoolprefimage",
      :puavoPersonalDevice => true,
      :puavoSchoolHomePageURL => "schoolhomepagefordevice.example",
      :puavoAllowGuest => true
    )
    @school_without_fallback_value = School.create(
      :cn => "gryffindor2",
      :displayName => "Gryffindor2"
    )
    @server1 = create_server(
      :puavoHostname => "server1",
      :macAddress => "bc:5f:f4:56:59:71",
      :puavoSchool => @school.dn
    )
    @server2 = create_server(
      :puavoHostname => "server2",
      :macAddress => "bc:5f:f4:56:59:72"
    )
    @printer = Printer.create(
      :printerDescription => "printer1",
      :printerLocation => "school2",
      :printerMakeAndModel => "foo",
      :printerType => "1234",
      :printerURI => "socket://baz",
      :puavoServer => @server1.dn
    )

    @school.add_wireless_printer(@printer)

    # School#reload for some reason clears some attributes. Workaround it for
    # now.
    @school = School.find(@school.dn)

    test_organisation = LdapOrganisation.first # TODO: fetch by name
    test_organisation.puavoAllowGuest = "FALSE"
    test_organisation.puavoPersonalDevice = "FALSE"
    test_organisation.save!
  end

  describe "device information" do
    before(:each) do
      create_device(
        :puavoHostname => "athin",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoPreferredServer => @server1.dn,
        :puavoDeviceImage => "customimage",
        :puavoSchool => @school.dn,
        :puavoPersonalDevice => false,
        :puavoDefaultPrinter => "defaultprinter",
        :puavoAllowGuest => false,
        :puavoPrinterDeviceURI => "usb:/dev/usb/lp1",
        :puavoDeviceDefaultAudioSource => "alsa_input.pci-0000_00_1b.0.analog-stereo",
        :puavoDeviceDefaultAudioSink => "alsa_output.pci-0000_00_1b.0.analog-stereo"
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

    it "has default printer" do
      assert_equal "defaultprinter", @data["default_printer_name"]
    end

    it "has default input audio device" do
      assert_equal "alsa_input.pci-0000_00_1b.0.analog-stereo", @data["default_audio_source"]
    end

    it "has default sink audio device" do
      assert_equal "alsa_output.pci-0000_00_1b.0.analog-stereo", @data["default_audio_sink"]
    end

    it "has preferred language" do
      assert_equal "en", @data["preferred_language"]
    end

    it "has homepage from school" do
      assert_equal "schoolhomepagefordevice.example", @data["homepage"]
    end

    it "it prefers language from the school" do
      @school.preferredLanguage = "sv"
      @school.save!
      get "/v3/devices/athin"
      assert_200
      data = JSON.parse last_response.body

      assert_equal "sv", data["preferred_language"]
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

    it "has preferred language" do
      assert @data["preferred_language"]
      assert_equal "en", @data["preferred_language"]
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

  describe "Device#preferred_boot_image" do
    it "is used for thinclients" do
      @thin = create_device(
        :puavoHostname => "athin",
        :puavoDeviceType =>  "thinclient",
        :macAddress => "00:60:2f:28:DC:51",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school.dn,

        :puavoDeviceBootImage => "bootimage",
        :puavoDeviceImage => "normalimage"
      )
      @thin.save!

      get "/v3/devices/athin"
      assert_200
      data = JSON.parse last_response.body
      assert_equal "bootimage", data["preferred_boot_image"]
    end

    it "is preferred_image for fatclients" do
      @fat = create_device(
        :puavoHostname => "afat",
        :puavoDeviceType =>  "fatclient",
        :macAddress => "00:60:2f:E5:A1:37",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school.dn,

        :puavoDeviceBootImage => "bootimage",
        :puavoDeviceImage => "normalimage"
      )
      @fat.save!

      get "/v3/devices/afat"
      assert_200
      data = JSON.parse last_response.body
      assert_equal "normalimage", data["preferred_boot_image"]
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

  describe "device boot configuration" do
    before(:each) do
      @thinclient01 = create_device(
        :puavoHostname => "thinclient-01",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school.dn,
        :puavoDeviceBootImage => "deviceprefbootimage",
        :puavoDeviceImage => "deviceprefimage"
      )
      @thinclient02 = create_device(
        :puavoHostname => "thinclient-02",
        :macAddress => "bf:9a:8c:1b:e0:6b",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school.dn,
        :puavoDeviceImage => "deviceprefimage"
      )
      @thinclient03 = create_device(
        :puavoHostname => "thinclient-03",
        :macAddress => "bf:9a:8c:1b:e0:6b",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school.dn
      )
      @thinclient04 = create_device(
        :puavoHostname => "thinclient-04",
        :macAddress => "bf:9a:8c:1b:e0:6b",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school_without_fallback_value.dn
      )

      test_organisation = LdapOrganisation.first # TODO: fetch by name
      test_organisation.puavoDeviceImage = "organisationprefimage"
      test_organisation.save!

      LdapModel.setup(
        :organisation =>
          PuavoRest::Organisation.default_organisation_domain!,
        :rest_root => "http://" + CONFIG["default_organisation_domain"],
                      :credentials => { :dn => PUAVO_ETC.ldap_dn, :password => PUAVO_ETC.ldap_password }
      )
      @rest_thinclient01 = PuavoRest::Device.by_dn(@thinclient01.dn.to_s)
      @rest_thinclient02 = PuavoRest::Device.by_dn(@thinclient02.dn.to_s)
      @rest_thinclient03 = PuavoRest::Device.by_dn(@thinclient03.dn.to_s)
      @rest_thinclient04 = PuavoRest::Device.by_dn(@thinclient04.dn.to_s)
    end

    it "has preferred boot image by device" do
      assert_equal @rest_thinclient01.preferred_boot_image, "deviceprefbootimage"
    end

    it "has preferred boot image by device preferred image" do
      assert_equal @rest_thinclient02.preferred_boot_image, "deviceprefimage"
    end

    it "has preferred boot image by school preferred image" do
      assert_equal @rest_thinclient03.preferred_boot_image, "schoolprefimage"
    end
    it "has preferred boot image by organisation preferred image" do
      assert_equal @rest_thinclient04.preferred_boot_image, "organisationprefimage"
    end
    it "has not preferred boot image" do

    end
  end

  describe "wireless printer queues by device with school fallback" do

    before(:each) do
      create_device(
        :puavoHostname => "athin",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school.dn
      )
    end

    it "has printer" do
      get "/v3/devices/athin/wireless_printer_queues", {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200
      data = JSON.parse last_response.body
      assert_equal 1, data.count
      printer = data.first
      assert_equal "server1.www.example.net", printer["server_fqdn"]
      assert_equal "printer1", printer["name"]
      assert_equal "printer1", printer["description"]
      assert_equal "ipp://server1.www.example.net/printers/printer1", printer["remote_uri"]
    end

    it "can handle multiple printers" do

      printer2 = Printer.create(
        :printerDescription => "printer2",
        :printerLocation => "school2",
        :printerMakeAndModel => "foo",
        :printerType => "1234",
        :printerURI => "socket://baz",
        :puavoServer => @server1.dn
      )
      printer2.save!
      @school.add_wireless_printer(printer2)

      get "/v3/devices/athin/wireless_printer_queues", {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200
      data = JSON.parse last_response.body

      assert_equal 2, data.count
      assert(
        data.select do |p|
          p["name"] == "printer2"
        end.first,
        "must have the second printer"
      )
    end
  end
end

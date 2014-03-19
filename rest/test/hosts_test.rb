require_relative "./helper"

describe PuavoRest::Host do

  @host_types = [ "thinclient",
                  "fatclient",
                  "ltspserver",
                  "laptop",
                  "unregistered" ]
  before(:each) do
    Puavo::Test.clean_up_ldap
    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor",
      :puavoDeviceImage => "schoolprefimage"
    )
    @host = {}
    @host["thinclient"] = create_device(
      :puavoHostname => "thinclient05",
      :puavoDeviceType => "thinclient",
      :macAddress => "bf:9a:8c:1b:e0:6a",
      :puavoDeviceKernelVersion => "thinkernel",
      :puavoSchool => @school.dn
    )
    @host["laptop"] = create_device(
      :puavoHostname => "laptop05",
      :puavoDeviceType => "laptop",
      :macAddress => "bf:9a:8c:1b:e0:6b",
      :puavoDeviceKernelVersion => "laptopkernel",
      :puavoSchool => @school.dn
    )
    @host["fatclient"] = create_device(
      :puavoHostname => "fatclient05",
      :puavoDeviceType => "fatclient",
      :macAddress => "bf:9a:8c:1b:e0:6c",
      :puavoDeviceKernelVersion => "fatkernel",
      :puavoSchool => @school.dn
    )

    @host["ltspserver"] = create_server(
      :puavoHostname => "ltspserver05",
      :macAddress => "bf:9a:8c:1b:e0:6d",
      :puavoDeviceKernelVersion => "ltspserverkernel",
      :puavoDeviceType => "ltspserver"
    )

    LdapModel.setup(
      :organisation =>
        PuavoRest::Organisation.default_organisation_domain!,
      :rest_root => "http://" + CONFIG["default_organisation_domain"],
                    :credentials => { :dn => PUAVO_ETC.ldap_dn, :password => PUAVO_ETC.ldap_password }
    )

    @rest_host = {}
    @rest_host["thinclient"] = PuavoRest::Device.by_dn(@host["thinclient"].dn)
    @rest_host["laptop"] = PuavoRest::Device.by_dn(@host["laptop"].dn)
    @rest_host["fatclient"] = PuavoRest::Device.by_dn(@host["fatclient"].dn)
    @rest_host["ltspserver"] = PuavoRest::LtspServer.by_dn(@host["ltspserver"].dn)
    @rest_host["unregistered"] = PuavoRest::Device.new
  end
  
  @host_types.each do |host_type|

    describe "as #{host_type}" do

      it "has grub type" do
        assert_equal @rest_host[host_type].grub_type, host_type
      end

      it "has grub kernel version" do
        if host_type == "unregistered"
          kernel_version = "" 
        else
          kernel_version = "-" + @host[host_type]["puavoDeviceKernelVersion"]
        end
        assert_equal @rest_host[host_type].grub_kernel_version, kernel_version
      end

    end
  end


  describe "boot time" do

    before(:each) do
      @org_log = $rest_flog
      @logger = MockFluent.new
      $rest_flog = @org_log.merge(nil, @logger)
    end

    after(:each) do
      $rest_flog = @org_log
    end

    it "will be logged" do
      thin = @host["thinclient"]


      get "/v3/boot_configurations/#{ thin.mac_address }"
      assert_200

      Timecop.travel 60

      post "/v3/boot_done/#{ thin.puavoHostname }", {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200
      data = JSON.parse(last_response.body)

      assert data["boot_duration"], "should have boot time field"
      assert_equal Fixnum, data["boot_duration"].class, data["boot_duration"]

      assert(
        data["boot_duration"] > 50,
        "boot duration (#{ data["boot_duration"] }) should be more than 50"
      )

      boot_start = @logger.data.select do |l|
        l[1][:msg] == "send boot configuration"
      end.first
      assert boot_start, "send boot configuration was logged"

      boot_end = @logger.data.select do |l|
        l[1][:msg] == "boot done"
      end.first

      assert boot_end, "boot end was logged"

      assert(
        boot_end[1]["boot done"][:boot_duration] > 55,
        "has boot duration near 60: #{ boot_end[1][:boot_duration] }"
      )

      assert_equal "thinclient05", boot_end[1]["boot done"][:hostname]


    end
  end



end

require_relative "./helper"

describe PuavoRest::Host do

  before(:each) do
    Puavo::Test.clean_up_ldap
    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor",
      :puavoDeviceImage => "schoolprefimage"
    )
    @host = {}
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

    setup_ldap_admin_connection()

    @rest_host = {}
    @rest_host["laptop"] = PuavoRest::Device.by_dn(@host["laptop"].dn)
    @rest_host["fatclient"] = PuavoRest::Device.by_dn(@host["fatclient"].dn)
    @rest_host["unregistered"] = PuavoRest::Device.new
  end

  describe "boot time" do

    before(:each) do
      @org_log = $rest_flog_base
      @logger = MockFluent.new
      $rest_flog_base = @org_log.merge(nil, @logger)
    end

    after(:each) do
      $rest_flog_base = @org_log
    end

    it "will be logged" do
      fat = @host["fatclient"]


      get "/v3/bootparams_by_mac/#{ fat.mac_address }", {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200

      Timecop.travel 60

      post "/v3/boot_done/#{ fat.puavoHostname }", {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200
      data = JSON.parse(last_response.body)

      assert data["boot_duration"], "should have boot time field"
      assert_equal Integer, data["boot_duration"].class, data["boot_duration"]

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

      assert_equal "fatclient05", boot_end[1]["boot done"][:hostname]


    end
  end



end

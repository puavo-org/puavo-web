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
end

require "set"
require_relative "./helper"

describe PuavoRest::BootConfigurations do

  before(:each) do
    Puavo::Test.clean_up_ldap
    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor",
      :puavoDeviceImage => "schoolprefimage"
    )

    create_device(
      :puavoHostname => "thinclient05",
      :puavoDeviceType => "thinclient",
      :macAddress => "bf:9a:8c:1b:e0:6a",
      :puavoDeviceKernelArguments => "ACPI",
      :puavoSchool => @school.dn
    )

    @server3 = create_server(
      :puavoHostname => "server3",
      :macAddress => "bc:5f:f4:56:59:73",
      :puavoDeviceType => "ltspserver"
    )

    @boot_server = create_server(
      :puavoHostname => "bootserver",
      :macAddress => "00:60:2f:E5:09:B4",
      # :puavoDeviceImage => "bootserverimage",
      :puavoDeviceType => "bootserver"
    )
    PuavoRest.test_boot_server_dn = @boot_server.dn.to_s

    test_organisation = LdapOrganisation.first # TODO: fetch by name
    test_organisation.puavoDeviceImage = "organisationprefimage"
    test_organisation.save!
  end

  describe "device" do

    before(:each) do
      get "/v3/bf:9a:8c:1b:e0:6a/boot_configuration", {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200
      @data = last_response.body
    end

    it "has following boot configuration" do
      configuration =<<EOF
default ltsp-NBD
ontimeout ltsp-NBD


label ltsp-NBD
  menu label LTSP, using NBD
  menu default
  kernel ltsp/schoolprefimage/vmlinuz
  append ro initrd=ltsp/schoolprefimage/initrd.img init=/sbin/init-puavo puavo.hosttype=thinclient root=/dev/nbd0 nbdroot=:schoolprefimage ACPI usbcore.autosuspend=-1
  ipappend 2
EOF
      assert_equal configuration, @data
    end
  end

  describe "ltsp server" do

    before(:each) do
      get "/v3/bc:5f:f4:56:59:73/boot_configuration", {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200
      @data = last_response.body
    end

    it "has following boot configuration" do
      configuration =<<EOF
default ltsp-NBD
ontimeout ltsp-NBD


label ltsp-NBD
  menu label LTSP, using NBD
  menu default
  kernel ltsp/organisationprefimage/vmlinuz
  append ro initrd=ltsp/organisationprefimage/initrd.img init=/sbin/init-puavo puavo.hosttype=ltspserver root=/dev/nbd0 nbdroot=:organisationprefimage quiet splash
  ipappend 2
EOF
      assert_equal configuration, @data
    end
  end

  describe "unregistered device" do

    it "has following boot configuration too" do
      get "/v3/bf:9a:8c:1b:e0:77/boot_configuration", {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200
      @data = last_response.body

      configuration =<<EOF
default ltsp-NBD
ontimeout ltsp-NBD


label ltsp-NBD
  menu label LTSP, using NBD
  menu default
  kernel ltsp/organisationprefimage/vmlinuz
  append ro initrd=ltsp/organisationprefimage/initrd.img init=/sbin/init-puavo puavo.hosttype=unregistered root=/dev/nbd0 nbdroot=:organisationprefimage 
  ipappend 2
EOF
      assert_equal configuration, @data
    end

    it "prefers boot server image over organisation image" do

      @boot_server.puavoDeviceImage = "bootserverimage"
      @boot_server.save!

      get "/v3/bf:9a:8c:1b:e0:77/boot_configuration", {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200
      @data = last_response.body

      configuration =<<EOF
default ltsp-NBD
ontimeout ltsp-NBD


label ltsp-NBD
  menu label LTSP, using NBD
  menu default
  kernel ltsp/bootserverimage/vmlinuz
  append ro initrd=ltsp/bootserverimage/initrd.img init=/sbin/init-puavo puavo.hosttype=unregistered root=/dev/nbd0 nbdroot=:bootserverimage 
  ipappend 2
EOF
      assert_equal configuration, @data

    end



  end
end

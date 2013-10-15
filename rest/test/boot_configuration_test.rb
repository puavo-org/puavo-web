require "set"
require_relative "./helper"

describe PuavoRest::BootConfigurations do


  describe "device" do

    before(:each) do
      @school = School.create(
        :cn => "gryffindor",
        :displayName => "Gryffindor",
        :puavoDeviceImage => "schoolprefimage"
      )
      create_device(
        :puavoHostname => "thinclient05",
        :puavoDeviceType => "thinclient",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoSchool => @school.dn
      )
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
  append ro initrd=ltsp/schoolprefimage/initrd.img init=/sbin/init-puavo puavo.hosttype=thinclient root=/dev/nbd0 nbdroot=:schoolprefimage 
  ipappend 2
EOF
      assert_equal configuration, @data
    end
  end


end

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
      :puavoHostname => "fatclient05",
      :puavoDeviceType => "fatclient",
      :macAddress => "bf:9a:8c:1b:e0:6a",
      :puavoDeviceKernelArguments => "ACPI",
      :puavoSchool => @school.dn
    )

    @boot_server = create_server(
      :puavoHostname        => 'bootserver',
      :macAddress           => '00:60:2f:E5:09:B4',
      :puavoDeviceBootImage => 'bootserverbootprefimage',
      :puavoDeviceImage     => 'bootserverimage',
      :puavoDeviceType      => 'bootserver',
    )
    PuavoRest.test_boot_server_dn = @boot_server.dn.to_s

    test_organisation = LdapOrganisation.first # TODO: fetch by name
    test_organisation.puavoDeviceImage = "organisationprefimage"
    test_organisation.save!
  end

  describe "device" do

    before(:each) do
      get '/v3/bootparams_by_mac/bf:9a:8c:1b:e0:6a', {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200
      @data = JSON.parse(last_response.body)
    end

    it "has following boot configuration" do
      assert @data.kind_of?(Hash)
      assert_equal 'schoolprefimage', @data['preferred_boot_image']
    end
  end

  describe "unregistered device" do

    it "has following boot configuration too" do
      get '/v3/bootparams_by_mac/bf:9a:8c:1b:e0:77', {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200
      @data = JSON.parse(last_response.body)

      assert @data.kind_of?(Hash)
      assert_equal 'bootserverbootprefimage', @data['preferred_boot_image']
    end

    it "prefers boot server image over organisation image" do

      @boot_server.puavoDeviceImage = "bootserverimage"
      @boot_server.save!

      get '/v3/bootparams_by_mac/bf:9a:8c:1b:e0:77', {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200
      @data = JSON.parse(last_response.body)

      assert @data.kind_of?(Hash)
      assert_equal 'bootserverbootprefimage', @data['preferred_boot_image']
    end

  end
end

require_relative "./helper"

describe PuavoRest::WlanNetworks do
  describe "wlan settings" do
    before(:each) do
      Puavo::Test.clean_up_ldap

      test_organisation = LdapOrganisation.first
      test_organisation.puavoDeviceImage = "organisationimage"
      test_organisation.wlan_networks = [
        {
          :ssid => "orgwlan",
          :type => "open",
          :wlan_ap => true,
          :password => "secret"
        },
        {
          :ssid => "3rdpartywlan",
          :type => "open",
          :wlan_ap => false,
          :password => "secret"
        }
      ]
      test_organisation.save!

      @school = School.create(
        :cn => "gryffindor",
        :displayName => "Gryffindor",
        :puavoDeviceImage => "schoolprefimage"
      )
      @school.wlan_networks = [
        {
          :ssid => "schoolwlan",
          :type => "open",
          :wlan_ap => true,
          :password => "secret"
        }
      ]
      @school.save!


      create_device(
        :puavoHostname => "athin",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoSchool => @school.dn
      )

    end

    describe "wlan client configuration" do

      before(:each) do
        get "/v3/devices/athin/wlan_networks"
        assert_200
        @data = JSON.parse last_response.body
      end

      it "is set from school" do
        assert_equal 1, (@data.select do |wlan|
          wlan["ssid"] == "schoolwlan"
        end).size
      end

      it "is set from organisation" do
        assert_equal 1, (@data.select do |wlan|
          wlan["ssid"] == "orgwlan"
        end).size
      end

      it "has 3rdparty networks too" do
        assert_equal 1, (@data.select do |wlan|
          wlan["ssid"] == "3rdpartywlan"
        end).size
      end

    end

    describe "wlan hotspot configuration" do

      before(:each) do
        get "/v3/devices/athin/wlan_hotspot_configurations"
        assert_200
        @data = JSON.parse last_response.body
      end

      it "does not have 3rd party networks" do
        assert_equal 0, (@data.select do |wlan|
          wlan["ssid"] == "3rdpartywlan"
        end).size
      end


    end

  end
end

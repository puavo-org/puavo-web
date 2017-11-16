require "set"
require_relative "./helper"

describe PuavoRest::WlanNetworks do
  describe "wlan settings" do
    before(:each) do
      Puavo::Test.clean_up_ldap

      @test_organisation = LdapOrganisation.first
      @test_organisation.puavoDeviceImage = "organisationimage"
      @test_organisation.wlan_networks = [
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
      @test_organisation.save!

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
        },
        {
          :ssid => "pskschoolwlan",
          :type => "psk",
          :wlan_ap => true,
          :password => "actuallysecret"
        },
        {
          :ssid => "eaptlsschoolwlan",
          :type => "eap-tls",
          :wlan_ap => false,
          :identity => 'Puavo',
          :certs => {
            'ca_cert' => '<CACERT>',
            'client_cert' => '<CLIENTCERT>',
            'client_key' => '<CLIENTKEY>',
            'client_key_password' => 'mysecretclientkeypassword',
          }
        }
      ]
      @school.save!

      @laptop1 = Device.new
      @laptop1.classes = ["top", "device", "puppetClient", "puavoLocalbootDevice", "simpleSecurityObject"]
      @laptop1.attributes = {
        :puavoHostname   => "laptop1",
        :puavoDeviceType => "laptop",
        :macAddress      => "bf:9a:8c:1b:e0:6a",
      }
      @laptop1.puavoSchool = @school.dn
      @laptop1.save!
    end

    describe "wlan client configuration" do

      before(:each) do
        get "/v3/devices/#{ @laptop1.puavoHostname }/wlan_networks"
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

    describe "wlan client configuration with same ssid" do

      it "has no duplicat ssid value" do
        @test_organisation.wlan_networks = [
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
          },
          {
            :ssid => "schoolwlan",
            :type => "open",
            :wlan_ap => true,
            :password => "secret"
          }
        ]
        @test_organisation.save!

        get "/v3/devices/#{ @laptop1.puavoHostname }/wlan_networks"
        assert_200
        data = JSON.parse last_response.body

        assert data.select { |w| w["ssid"] == "schoolwlan" }.count == 1, "Duplicate ssid value!"
      end

    end

    describe "wlan client configuration with eap-tls certificates" do
      before(:each) do
        basic_authorize @laptop1.dn, @laptop1.ldap_password
        get "/v3/devices/#{ @laptop1.puavoHostname }/wlan_networks_with_certs"
        assert_200
        @data = JSON.parse last_response.body
      end

      it "we have all school and organisation networks" do
        expected_ssids = \
          %w(3rdpartywlan eaptlsschoolwlan orgwlan pskschoolwlan schoolwlan)
        assert_equal expected_ssids, (@data.map { |wlan| wlan['ssid'] }.sort)
      end

      it "we have the certificates from eaptlsschoolwlan" do
        wlans = @data.select { |wlan| wlan['ssid'] == 'eaptlsschoolwlan' }
        assert_equal 1, wlans.count

        eaptlsschoolwlan = wlans.first
        certs = eaptlsschoolwlan['certs']
        assert certs.kind_of?(Hash), 'has certs hash'

        assert_equal certs['ca_cert'],             '<CACERT>'
        assert_equal certs['client_cert'],         '<CLIENTCERT>'
        assert_equal certs['client_key'],          '<CLIENTKEY>'
        assert_equal certs['client_key_password'], 'mysecretclientkeypassword'
      end
    end

    describe "lecacy configuration" do

      it "is ignored from school" do
        @school.puavoWlanSSID = "fuuck:oldie:here"
        @school.save!

        get "/v3/devices/#{ @laptop1.puavoHostname }/wlan_networks"
        assert_200
        data = JSON.parse last_response.body

        assert_equal(
          Set.new(["orgwlan", "3rdpartywlan"]),
          Set.new(data.map { |w| w["ssid"] })
        )
      end

      it "is ignored from organisation" do
        @test_organisation.puavoWlanSSID = "fuuck:oldie:here"
        @test_organisation.save!

        get "/v3/devices/#{ @laptop1.puavoHostname }/wlan_networks"
        assert_200
        data = JSON.parse last_response.body

        assert_equal(
          Set.new(["schoolwlan", "pskschoolwlan"]),
          Set.new(data.map { |w| w["ssid"] })
        )
      end

    end


    describe "wlan hotspot configuration" do

      before(:each) do
        get "/v3/devices/#{ @laptop1.puavoHostname }/wlan_hotspot_configurations"
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

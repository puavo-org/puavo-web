require "set"
require_relative "./helper"

describe PuavoRest::WlanNetworks do
  def create_laptop(hostname, mac_address, school_dn)
    laptop = Device.new
    laptop.classes \
      = %w(top device puppetClient puavoLocalbootDevice simpleSecurityObject)
    laptop.attributes = {
      :puavoHostname   => hostname,
      :puavoDeviceType => 'laptop',
      :macAddress      => mac_address,
    }
    laptop.puavoSchool = school_dn
    laptop.save!

    laptop
  end

  def get_wlan_networks_with_certs(device)
    basic_authorize device.dn, device.ldap_password
    get "/v3/devices/#{ device.puavoHostname }/wlan_networks_with_certs"
    assert_200
    JSON.parse last_response.body
  end

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

      @laptop1 = create_laptop('laptop1', 'bf:9a:8c:1b:e0:6a', @school.dn)
      @laptop2 = create_laptop('laptop2', '6a:e0:1b:8c:9a:bf', @school.dn)
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
      it "we have all school and organisation networks" do
        data = get_wlan_networks_with_certs(@laptop1)
        expected_ssids = \
          %w(3rdpartywlan eaptlsschoolwlan orgwlan pskschoolwlan schoolwlan)
        assert_equal expected_ssids, (data.map { |wlan| wlan['ssid'] }.sort)
      end

      it "we have the certificates from eaptlsschoolwlan" do
        data = get_wlan_networks_with_certs(@laptop1)
        wlans = data.select { |wlan| wlan['ssid'] == 'eaptlsschoolwlan' }
        assert_equal 1, wlans.count

        eaptlsschoolwlan = wlans.first

        assert_equal 'Puavo', eaptlsschoolwlan['identity']

        certs = eaptlsschoolwlan['certs']
        assert certs.kind_of?(Hash), 'has certs hash'

        assert_equal '<CACERT>',                  certs['ca_cert']
        assert_equal '<CLIENTCERT>',              certs['client_cert']
        assert_equal '<CLIENTKEY>',               certs['client_key']
        assert_equal 'mysecretclientkeypassword', certs['client_key_password']
      end

      it "getting eap-tls certificates of another machine should fail" do
        basic_authorize @laptop2.dn, @laptop2.ldap_password
        get "/v3/devices/#{ @laptop1.puavoHostname }/wlan_networks_with_certs"
        assert_equal 404, last_response.status
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

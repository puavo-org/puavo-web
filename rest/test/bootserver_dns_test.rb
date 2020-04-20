require_relative './helper'

describe PuavoRest::BootserverDNS do

  before(:each) do
    Puavo::Test.clean_up_ldap
      @school = School.create(
        :cn               => 'gryffindor',
        :displayName      => 'Gryffindor',
        :puavoDeviceImage => 'schoolprefimage')

      @host = create_device(:puavoHostname   => 'a-computing-device-01',
                            :puavoDeviceType => 'fatclient',
                            :macAddress      => '00:61:2e:c5:33:af',
                            :puavoSchool     => @school.dn)

      @dns_update_params = {
        'client_mac' => @host.macAddress,
        'client_ip'  => '10.249.12.34',
        'dry_run'    => true,		# we do not test the actual DNS updates
        'key_name'   => 'ddns-key',
        'key_secret' => 'n0FG8QLzMC6vKhqW61NWeQ==',
        'subdomain'  => 'ltsp',
        'type'       => 'mac',
      }
  end
 
  describe "update host DNS records" do
    it 'updates DNS for host' do
      post '/v3/bootserver_dns_update', @dns_update_params, {
        'HTTP_AUTHORIZATION' => 'Bootserver'
      }

      assert_200

      expected_fqdn = "#{ @host.puavoHostname }.#{ @dns_update_params['subdomain'] }" \
                        + '.example.puavo.net'

      data = JSON.parse last_response.body
      assert data.kind_of?(Hash)
      assert_equal 'successfully', data['status']
      assert_equal expected_fqdn, data['client_fqdn']
    end

    it 'wrong DNS update type is rejected' do
      dns_update_params = @dns_update_params.merge({ :type => 'badtype' })
      post '/v3/bootserver_dns_update', dns_update_params, {
        'HTTP_AUTHORIZATION' => 'Bootserver'
      }

      assert_equal 400, last_response.status
    end

    it 'host with mac address not found returns 404' do
      dns_update_params \
        = @dns_update_params.merge({ :client_mac => '00:11:22:33:44:55' })

      post '/v3/bootserver_dns_update', dns_update_params, {
        'HTTP_AUTHORIZATION' => 'Bootserver'
      }

      assert_equal 404, last_response.status
    end
  end
end

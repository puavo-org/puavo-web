# OAuth2 access token tests

require 'addressable/uri'
require 'argon2'
require 'jwt'

require_relative 'helper'
require_relative 'oauth2_helpers'

describe PuavoRest::OAuth2 do
  before(:each) do
    Puavo::Test.clean_up_ldap

    setup_oauth2_database
    setup_ldap_admin_connection()
  end

  after(:each) do
    oauth2_client_db do |db|
      delete_test_client_data(db)
    end
  end

  # Sets up the common clients used in these tests
  def setup_oauth2_database
    common_password_hash = Argon2::Password.new(profile: :rfc_9106_low_memory).create('supersecretpassword')

    oauth2_client_db do |db|
      delete_test_client_data(db)

      create_token_client(db, 'test_client_users_groups', ['puavo.read.users', 'puavo.read.groups'], endpoints: ['/v4/users', '/v4/groups'])
      create_client_authentication(db, 'test_client_users_groups', 'client_secret_basic', params: { password_hash: common_password_hash })
      create_client_authentication(db, 'test_client_users_groups', 'client_secret_post', params: { password_hash: common_password_hash })
      create_token_client(db, 'test_client_devices', ['puavo.read.devices'], endpoints: ['/v4/devices'])
      create_client_authentication(db, 'test_client_devices', 'client_secret_basic', params: { password_hash: common_password_hash })
      create_token_client(db, 'test_client_users1', ['puavo.read.users', 'puavo.read.groups'], endpoints: ['/v4/users'])
      create_client_authentication(db, 'test_client_users1', 'client_secret_basic', params: { password_hash: common_password_hash })
      create_token_client(db, 'test_client_users2', ['puavo.read.users', 'puavo.read.groups'], endpoints: ['/v4/users', '/v4/groups'])
      create_client_authentication(db, 'test_client_users2', 'client_secret_basic', params: { password_hash: common_password_hash })
      create_token_client(db, 'test_client_wrong_ldap_id', ['puavo.read.users'], endpoints: ['/v4/users'], ldap_id: 'foobar')
      create_client_authentication(db, 'test_client_wrong_ldap_id', 'client_secret_basic', params: { password_hash: common_password_hash })

      # The required service DN is inserted later, when this client is actually used
      create_token_client(db, 'test_client_required_dn', ['puavo.read.users'], endpoints: ['/v4/users'])
      create_client_authentication(db, 'test_client_required_dn', 'client_secret_basic', params: { password_hash: common_password_hash })
    end
  end

  # Acquires an OAuth2 access token using client_secret_basic authentication (ie. the normal HTTP basic auth)
  def acquire_token(client_id, client_secret, scopes)
    url = Addressable::URI.parse('/oidc/token')

    url.query_values = {
      'grant_type' => 'client_credentials',
      'scope' => scopes.join(' '),
    }

    basic_authorize client_id, client_secret

    post url.to_s
  end

  # Acquires an OAuth2 access token using client_secret_post authentication
  def acquire_token_client_secret_post(client_id, client_secret, scopes)
    url = Addressable::URI.parse('/oidc/token')

    url.query_values = {
      'client_id' => client_id,
      'client_secret' => client_secret,
      'grant_type' => 'client_credentials',
      'scope' => scopes.join(' ')
    }

    post url.to_s
  end

  # Authenticates a request with an OAuth2 token
  def fetch_data_with_token(access_token, url, fields)
    url = Addressable::URI.parse(url)

    url.query_values = {
      'fields' => fields
    }

    header 'Host', 'example.puavo.net'
    header 'Authorization', "Bearer #{access_token}"

    get url.to_s
  end

  describe 'miscellaneous tests' do
    before(:each) do
      oauth2_client_db do |db|
        create_token_client(db, 'test_client_disabled', ['puavo.read.users'], endpoints: ['/v4/users'], enabled: false)
        create_client_authentication(db, 'test_client_disabled', 'client_secret_basic', params: { password: 'disabled_client_password' })
      end
    end

    it 'ask for something else than client credentials' do
      url = Addressable::URI.parse('/oidc/token')

      url.query_values = {
        'grant_type' => 'spherical_cow',
        'scope' => 'puavo.read.users',
      }

      # This client does not exist, but it doesn't matter since the grant type is checked first
      basic_authorize 'users_client', 'supersecretpassword'
      post url.to_s

      assert_equal last_response.status, 400
      response = JSON.parse last_response.body
      assert_equal response['error'], 'unsupported_grant_type'
      assert_equal response['iss'], 'https://api.opinsys.fi'
    end

    it 'trying to use a disabled client must fail' do
      url = Addressable::URI.parse('/oidc/token')

      url.query_values = {
        'grant_type' => 'client_credentials',
        'scope' => 'puavo.read.users',
      }

      basic_authorize 'test_client_disabled', 'disabled_client_password'
      post url.to_s

      assert_equal last_response.status, 400
      response = JSON.parse last_response.body
      assert_equal response['error'], 'unauthorized_client'
      assert_equal response['iss'], 'https://api.opinsys.fi'
    end

    it 'invalid client ID rejection tests' do
      ['a', 'aa', 'aaa', 'a' * 33, 'client_!"#%', '3foo', 'FOOBAR', '{{{{{{', 'öööö', 'foo bar', 'client_❌', '➕➖➗🟰🧮️', 'hölökyn kölökyn'].each do |id|
        acquire_token(id, 'supersecretpassword', ['puavo.read.users', 'puavo.read.groups'])
        assert_equal last_response.status, 400
        response = JSON.parse(last_response.body)
        assert_equal response['error'], 'unauthorized_client'
      end
    end
  end

  describe 'credentials testing' do
    it 'no credentials in request will fail' do
      # Duplicate acquire_token's content here
      url = Addressable::URI.parse('/oidc/token')

      url.query_values = {
        'grant_type' => 'client_credentials',
        'scope' => 'puavo.read.users',
      }

      post url.to_s

      assert_equal last_response.status, 400
      response = JSON.parse last_response.body
      assert_equal response['error'], 'unauthorized_client'
      assert_equal response['iss'], 'https://api.opinsys.fi'
    end

    it 'wrong client credentials will fail (1)' do
      acquire_token('foo', 'foo', ['puavo.read.users'])

      assert_equal last_response.status, 400
      response = JSON.parse last_response.body
      assert_equal response['error'], 'unauthorized_client'
      assert_equal response['iss'], 'https://api.opinsys.fi'
    end

    it 'wrong client credentials will fail (2)' do
      acquire_token('test_client_users_groups', 'wrong password', ['puavo.read.users'])

      assert_equal last_response.status, 400
      response = JSON.parse last_response.body
      assert_equal response['error'], 'unauthorized_client'
      assert_equal response['iss'], 'https://api.opinsys.fi'
    end

    it 'wrong client credentials will fail (3)' do
      acquire_token('foo', 'supersecretpassword', ['puavo.read.users'])

      assert_equal last_response.status, 400
      response = JSON.parse last_response.body
      assert_equal response['error'], 'unauthorized_client'
      assert_equal response['iss'], 'https://api.opinsys.fi'
    end
  end

  describe 'JWT validation tests' do
    it 'invalid audience' do
      acquire_token('test_client_users_groups', 'supersecretpassword', ['puavo.read.users', 'puavo.read.groups'])

      assert_equal last_response.status, 200
      response = JSON.parse last_response.body
      assert response['access_token']
      assert_equal response['token_type'], 'Bearer'

      exception = assert_raises JWT::InvalidAudError do
        decode_token(response['access_token'], audience: 'foo')
      end
    end

    it 'invalid key (1)' do
      acquire_token('test_client_users_groups', 'supersecretpassword', ['puavo.read.users', 'puavo.read.groups'])

      assert_equal last_response.status, 200
      response = JSON.parse last_response.body
      assert response['access_token']
      assert_equal response['token_type'], 'Bearer'

      exception = assert_raises JWT::DecodeError do
        decode_token(response['access_token'], key: nil)
      end

      assert_equal exception.to_s, 'No verification key available'
    end

    it 'invalid key (2)' do
      acquire_token('test_client_users_groups', 'supersecretpassword', ['puavo.read.users', 'puavo.read.groups'])

      assert_equal last_response.status, 200
      response = JSON.parse last_response.body
      assert response['access_token']
      assert_equal response['token_type'], 'Bearer'

      exception = assert_raises JWT::VerificationError do
        # The "other key" is actually a real, working public key I generated for this test.
        # It's just not the key we need to validate the generated token.
        other_key = OpenSSL::PKey.read(File.read(File.join(File.dirname(__FILE__), 'fixtures', 'other_public_key.pem')))
        decode_token(response['access_token'], key: other_key)
      end

      assert_equal exception.to_s, 'Signature verification failed'
    end

    it 'simulate a token that has been tampered with' do
      acquire_token('test_client_users_groups', 'supersecretpassword', ['puavo.read.users', 'puavo.read.groups'])

      assert_equal last_response.status, 200
      response = JSON.parse last_response.body
      assert response['access_token']
      assert_equal response['token_type'], 'Bearer'

      # "tamper" with the data
      response['access_token'][100] = 'x'

      exception = assert_raises JWT::VerificationError do
        decode_token(response['access_token'])
      end

      assert_equal exception.to_s, 'Signature verification failed'
    end
  end

  describe 'scopes testing' do
    it 'non-existent scope' do
      acquire_token('test_client_users_groups', 'supersecretpassword', ['puavo.write.users'])

      assert_equal last_response.status, 400
      response = JSON.parse last_response.body
      assert_equal response['error'], 'invalid_scope'
      assert_equal response['iss'], 'https://api.opinsys.fi'
    end

    it 'acquire an access token with smaller scopes' do
      acquire_token('test_client_users_groups', 'supersecretpassword', ['puavo.read.users'])

      assert_equal last_response.status, 200
      response = JSON.parse last_response.body
      assert response['access_token']
      assert_equal response['token_type'], 'Bearer'

      access_token = decode_token(response['access_token'])
      assert_equal access_token['iss'], 'https://api.opinsys.fi'
      assert_equal access_token['scopes'], 'puavo.read.users'
    end

    it 'excessive scopes are reduced (1)' do
      acquire_token('test_client_users_groups', 'supersecretpassword', ['puavo.read.users', 'puavo.read.groups', 'puavo.read.schools'])

      assert_equal last_response.status, 200
      response = JSON.parse last_response.body
      assert response['access_token']
      assert_equal response['token_type'], 'Bearer'

      access_token = decode_token(response['access_token'])
      assert_equal access_token['iss'], 'https://api.opinsys.fi'
      assert_equal access_token['scopes'], 'puavo.read.users puavo.read.groups'
    end

    it 'excessive scopes are reduced (2)' do
      acquire_token('test_client_users_groups', 'supersecretpassword', ['puavo.read.users', 'puavo.read.groups', 'puavo.read.schools', 'foo', 'bar'])

      assert_equal last_response.status, 200
      response = JSON.parse last_response.body
      assert response['access_token']
      assert_equal response['token_type'], 'Bearer'

      access_token = decode_token(response['access_token'])
      assert_equal access_token['iss'], 'https://api.opinsys.fi'
      assert_equal access_token['scopes'], 'puavo.read.users puavo.read.groups'
    end

    it 'try to access something outside of the requested scopes' do
      acquire_token('test_client_devices', 'supersecretpassword', ['puavo.read.devices'])
      response = JSON.parse last_response.body
      access_token = response['access_token']
      decoded_token = decode_token(access_token)
      assert_equal decoded_token['iss'], 'https://api.opinsys.fi'

      # We have scopes for devices, so try to access groups
      fetch_data_with_token(access_token, '/v4/groups', 'id,abbreviation,name,type,school_id,member_uid')
      assert_equal last_response.status, 401
    end
  end

  describe 'various client authentication method tests' do
    it 'acquire a basic access token (client_secret_basic)' do
      acquire_token('test_client_users_groups', 'supersecretpassword', ['puavo.read.users', 'puavo.read.groups'])

      assert_equal last_response.status, 200
      response = JSON.parse last_response.body

      assert response['access_token']
      assert_equal response['token_type'], 'Bearer'

      access_token = decode_token(response['access_token'])
      assert_equal access_token['iss'], 'https://api.opinsys.fi'
      assert_equal access_token['scopes'], 'puavo.read.users puavo.read.groups'
    end

    it 'acquire a basic access token (client_secret_post)' do
      acquire_token_client_secret_post('test_client_users_groups', 'supersecretpassword', ['puavo.read.users', 'puavo.read.groups'])

      assert_equal last_response.status, 200
      response = JSON.parse last_response.body
      assert response['access_token']
      assert_equal response['token_type'], 'Bearer'

      access_token = decode_token(response['access_token'])
      assert_equal access_token['iss'], 'https://api.opinsys.fi'
      assert_equal access_token['scopes'], 'puavo.read.users puavo.read.groups'
    end

    it 'supply more than one authentication in one request' do
      client_id = 'test_client_users_groups'
      client_secret = 'supersecretpassword'

      url = Addressable::URI.parse('/oidc/token')

      # Put two different authentication methods in one request

      # client_secret_basic
      basic_authorize client_id, client_secret

      # client_secret_post
      url.query_values = {
        'client_id' => client_id,
        'client_secret' => client_secret,
        'grant_type' => 'client_credentials',
        'scope' => ['puavo.read.users', 'puavo.read.groups'].join(' ')
      }

      post url.to_s

      # The request must fail
      assert_equal last_response.status, 400
      response = JSON.parse last_response.body
      assert_nil response['access_token']
      assert_equal response['error'], 'unauthorized_client'
      assert_equal response['iss'], 'https://api.opinsys.fi'
    end
  end

  describe 'authentication record testing' do
    before do
      oauth2_client_db do |db|
        # This client has no authentication records at all, so while it exists it cannot be used
        create_token_client(db, 'test_client_no_client_auth', ['puavo.read.users'], endpoints: ['/v4/users'])

        # This client has two active overlapping records, so it won't work
        create_token_client(db, 'test_client_too_many_auths', ['puavo.read.users'], endpoints: ['/v4/users'])
        create_client_authentication(db, 'test_client_too_many_auths', 'client_secret_basic', params: { password: 'foo' })
        create_client_authentication(db, 'test_client_too_many_auths', 'client_secret_basic', params: { password: 'bar' })
      end
    end

    it 'missing client authentication records must fail' do
      acquire_token('test_client_no_client_auth', 'foobar', ['puavo.read.users'])

      assert_equal last_response.status, 400
      response = JSON.parse last_response.body
      assert_nil response['access_token']
      assert_equal response['error'], 'unauthorized_client'
      assert_equal response['iss'], 'https://api.opinsys.fi'
    end

    it 'more than one active record must fail' do
      acquire_token('test_client_too_many_auths', 'foo', ['puavo.read.users'])

      assert_equal last_response.status, 400
      response = JSON.parse last_response.body
      assert_nil response['access_token']
      assert_equal response['error'], 'unauthorized_client'
      assert_equal response['iss'], 'https://api.opinsys.fi'
    end
  end

  describe 'data retrieval with tokens' do
    # Create some test data
    before do
      school = School.create(
        cn: 'duckburg',
        displayName: 'Duckburg Elementary'
      )

      school.save!

      ducks_group = PuavoRest::Group.new(
        abbreviation: 'ducks',
        name: 'Ducks',
        school_dn: school.dn.to_s,
        type: 'teaching group'
      )

      ducks_group.save!

      @users = [
        ['Huey', 'Duck', 'huey.duck'],
        ['Dewey', 'Duck', 'dewey.duck'],
        ['Louie', 'Duck', 'louie.duck'],
        ['Phooey', 'Duck', 'phooey.duck']
      ]

      @users.each do |user|
        u = PuavoRest::User.new(
          first_name: user[0],
          last_name: user[1],
          username: user[2],
          roles: ['student'],
          school_dns: [school.dn.to_s],
        )

        u.save!
        u.teaching_group = ducks_group
      end
    end

    it 'retrieve users data with token authentication' do
      acquire_token('test_client_users_groups', 'supersecretpassword', ['puavo.read.users', 'puavo.read.groups'])
      response = JSON.parse last_response.body
      access_token = response['access_token']
      decoded_token = decode_token(access_token)

      assert_equal decoded_token['iss'], 'https://api.opinsys.fi'

      fetch_data_with_token(access_token, '/v4/users', 'id,first_names,last_name,username')

      assert_equal last_response.status, 200
      response = JSON.parse last_response.body

      assert_equal response['status'], 'ok'
      assert_nil response['error']
      assert_equal response['data'].length, 5   # the "cucumber" user is included in the results

      # Ensure every user we created exists in the data
      @users.each do |user|
        user2 = response['data'].find { |i| i['username'] == user[2] }

        assert user2
        assert_equal user2['first_names'], user[0]
        assert_equal user2['last_name'], user[1]
        assert_equal user2['username'], user[2]
      end
    end

    it 'retrieve users data with token authentication (2)' do
      acquire_token_client_secret_post('test_client_users_groups', 'supersecretpassword', ['puavo.read.users', 'puavo.read.groups'])
      response = JSON.parse last_response.body
      access_token = response['access_token']
      decoded_token = decode_token(access_token)

      assert_equal decoded_token['iss'], 'https://api.opinsys.fi'

      fetch_data_with_token(access_token, '/v4/users', 'id,first_names,last_name,username')

      assert_equal last_response.status, 200
      response = JSON.parse last_response.body

      assert_equal response['status'], 'ok'
      assert_nil response['error']
      assert_equal response['data'].length, 5   # the "cucumber" user is included in the results

      # Ensure every user we created exists in the data
      @users.each do |user|
        user2 = response['data'].find { |i| i['username'] == user[2] }

        assert user2
        assert_equal user2['first_names'], user[0]
        assert_equal user2['last_name'], user[1]
        assert_equal user2['username'], user[2]
      end
    end

    it 'token with an invalid LDAP mapping' do
      acquire_token('test_client_wrong_ldap_id', 'supersecretpassword', ['puavo.read.users', 'puavo.read.groups'])
      response = JSON.parse last_response.body
      access_token = response['access_token']
      decoded_token = decode_token(access_token)

      assert_equal decoded_token['iss'], 'https://api.opinsys.fi'

      fetch_data_with_token(access_token, '/v4/users', 'id,first_names,last_name,username')

      # Since no DN with "foobar" exits in the client mappings, the request must fail
      assert_equal last_response.status, 401
      response = JSON.parse last_response.body
      assert_equal response['error']['code'], 'InvalidOAuth2Token'
      assert_equal response['error']['message'], 'invalid_ldap_id'
    end

    it 'retrieve groups data with token authentication' do
      acquire_token('test_client_users_groups', 'supersecretpassword', ['puavo.read.users', 'puavo.read.groups'])
      response = JSON.parse last_response.body
      access_token = response['access_token']
      decoded_token = decode_token(access_token)

      assert_equal decoded_token['iss'], 'https://api.opinsys.fi'

      fetch_data_with_token(access_token, '/v4/groups', 'id,abbreviation,name,type,school_id,member_uid')

      assert_equal last_response.status, 200
      response = JSON.parse last_response.body

      assert_equal response['status'], 'ok'
      assert_nil response['error']
      assert_equal response['data'].length, 2

      group = response['data'].find { |i| i['abbreviation'] == 'ducks' }
      assert group

      # Ensure the group members are what they should be
      @users.each do |user|
        assert group['member_uid'].find { |i| i == user[2] }
      end
    end

    it 'cross-configured scopes/endpoints test 1' do
      # This client has users and groups scopes, but no access to the groups endpoint
      acquire_token('test_client_users1', 'supersecretpassword', ['puavo.read.users', 'puavo.read.groups'])
      response = JSON.parse last_response.body
      access_token = response['access_token']
      decoded_token = decode_token(access_token)
      assert_equal decoded_token['iss'], 'https://api.opinsys.fi'

      fetch_data_with_token(access_token, '/v4/groups', 'id,abbreviation,name,type,school_id,member_uid')
      assert_equal last_response.status, 403    # invalid endpoint
    end

    it 'cross-configured scopes/endpoints test 2' do
      # This client has access to both endpoints, but scopes only to one of them
      acquire_token('test_client_users2', 'supersecretpassword', ['puavo.read.users'])
      response = JSON.parse last_response.body
      access_token = response['access_token']
      decoded_token = decode_token(access_token)
      assert_equal decoded_token['iss'], 'https://api.opinsys.fi'

      fetch_data_with_token(access_token, '/v4/groups', 'id,abbreviation,name,type,school_id,member_uid')
      assert_equal last_response.status, 401    # invalid scopes
    end

    it 'expired token will not grant access' do
      # This is a valid access token. But it expired a long time ago and won't work anymore.
      expired_token = 'eyJ0eXAiOiJhdCtqd3QiLCJhbGciOiJFUzI1NiJ9.eyJqdGkiOiJiYzk4ZDFlNS01OTUyLTQ3ZT' + \
                      'QtYmI3Yi02OTBlOWE3MjRjOTgiLCJpYXQiOjE3Mzc1NDcyNDQsIm5iZiI6MTczNzU0NzI0NCwiZ' + \
                      'XhwIjoxNzM3NTUwODQ0LCJpc3MiOiJodHRwczovL2F1dGgub3BpbnN5cy5maSIsInN1YiI6InVz' + \
                      'ZXJzX2NsaWVudCIsImF1ZCI6InB1YXZvLXJlc3QtdjQiLCJzY29wZXMiOiJwdWF2by5yZWFkLnV' + \
                      'zZXJzIHB1YXZvLnJlYWQuZ3JvdXBzIiwiY2xpZW50X2lkIjoidXNlcnNfY2xpZW50IiwiYWxsb3' + \
                      'dlZF9lbmRwb2ludHMiOlsiL3Y0L3VzZXJzIl19.Rz_Q7nOFVDtox0QcI9x58It6m849q3EZ9DyH' + \
                      'rLS2wZqTg_9PXKq3dmLCtXdu41bUqlYVv789pMM5SEzT94VvpQ'

      # Ensure the JWT is not valid anymore
      assert_raises JWT::ExpiredSignature do
        JWT.decode(expired_token, load_default_public_key(), true, {
          algorithm: 'ES256',
          verify_iat: true,
          verify_iss: false,
          verify_aud: false,
        })
      end

      # Ensure it will not be accepted by puavo-rest either
      fetch_data_with_token(expired_token, '/v4/users', 'id,first_names,last_name,username')
      assert_equal last_response.status, 401
    end
  end

  describe 'required service DN tests' do
    before(:context) do
      # Create an external service
      PuavoRest::Organisation.refresh

      @external_service = ExternalService.new
      @external_service.classes = ['top', 'puavoJWTService']
      @external_service.cn = 'Temporary Service'
      @external_service.puavoServiceDomain = 'temporary.example.com'
      @external_service.puavoServiceSecret = 'secret'
      @external_service.puavoServiceTrusted = false
      @external_service.save!

      activate_organisation_services([@external_service.dn.to_s])

      # Update the token client entry
      oauth2_client_db do |db|
        db.exec_params('UPDATE token_clients SET required_service_dn = $1 WHERE client_id = $2;',
                       [@external_service.dn.to_s, 'test_client_required_dn'])
      end
    end

    it 'ensure the token contains a required service DN string' do
      acquire_token('test_client_required_dn', 'supersecretpassword', ['puavo.read.users'])

      assert_equal last_response.status, 200
      access_token = JSON.parse(last_response.body)['access_token']
      decoded_token = decode_token(access_token)

      assert_equal decoded_token['iss'], 'https://api.opinsys.fi'
      assert_equal decoded_token['required_service_dn'], @external_service.dn.to_s

      # Use the token
      fetch_data_with_token(access_token, '/v4/users', 'id,first_names,last_name,username')

      assert_equal last_response.status, 200
      response = JSON.parse last_response.body
      assert_equal response['status'], 'ok'
      assert_nil response['error']
      assert_equal response['data'].length, 1   # the "cucumber" user
    end

    it 'tamper with the data' do
      acquire_token('test_client_required_dn', 'supersecretpassword', ['puavo.read.users'])

      assert_equal last_response.status, 200
      access_token = JSON.parse(last_response.body)['access_token']
      decoded_token = decode_token(access_token)

      assert_equal decoded_token['iss'], 'https://api.opinsys.fi'
      assert_equal decoded_token['required_service_dn'], @external_service.dn.to_s

      # Change the required service DN to something that's unlikely to exist (and definitely not activated!)
      decoded_token['required_service_dn'] = 'puavoId=0,ou=Services,o=puavo'

      # Re-sign the token with the actual signing key. This works in puavo-standalone, but not in production.
      private_key = OpenSSL::PKey.read(File.read('/etc/puavo-rest.d/oauth2_token_signing_private_key_example.pem'))
      new_token = JWT.encode(decoded_token, private_key, 'ES256', { typ: 'at+jwt', kid: CONFIG['oauth2']['kid'] })

      # Then try to use the tampered token. It must fail.
      fetch_data_with_token(new_token, '/v4/users', 'id,first_names,last_name,username')

      assert_equal last_response.status, 403
      response = JSON.parse last_response.body
      assert_equal response['error']['code'], 'Forbidden'
      assert_equal response['error']['message'], 'invalid_token'
    end
  end

  describe 'JWKS tests' do
    it 'can decode a key with the built-in key in JWKS' do
      # Get a token
      acquire_token('test_client_users2', 'supersecretpassword', ['puavo.read.users'])
      response = JSON.parse last_response.body

      # Decode it using the default JWKs
      jwks = JSON.parse(File.read(CONFIG['oauth2']['key_files']['public_jwks']))
      decoded_token = decode_token_jwks(response['access_token'], jwks)
      assert_equal decoded_token['iss'], 'https://api.opinsys.fi'
    end

    it 'the other test key will not validate the issued token' do
      acquire_token('test_client_users2', 'supersecretpassword', ['puavo.read.users'])
      response = JSON.parse last_response.body

      # Load the other JWKS and manually change the KID to match the real key
      jwks = JSON.parse(File.read(File.join(File.dirname(__FILE__), 'fixtures', 'other_key_jwks.json')))
      jwks['keys'][0]['kid'] = 'puavo_standalone_20250115T095034Z'

      # This must now fail
      exception = assert_raises JWT::VerificationError do
        decode_token_jwks(response['access_token'], jwks)
      end

      assert_equal exception.to_s, 'Signature verification failed'
    end

    it 'custom signed token will open with the custom key' do
      other_key = OpenSSL::PKey.read(File.read(File.join(File.dirname(__FILE__), 'fixtures', 'other_private_key.pem')))
      token = sign_token_with_pem(other_key, subject: 'test subject', scopes: ['foo', 'bar'], kid: 'puavo_standalone_2_20250115T095034Z')

      jwks = JSON.parse(File.read(File.join(File.dirname(__FILE__), 'fixtures', 'other_key_jwks.json')))
      decoded_token = decode_token_jwks(token, jwks)
      assert_equal decoded_token['iss'], 'https://api.opinsys.fi'
    end

    it 'custom signed token will not open with the real key' do
      other_key = OpenSSL::PKey.read(File.read(File.join(File.dirname(__FILE__), 'fixtures', 'other_private_key.pem')))
      token = sign_token_with_pem(other_key, subject: 'test subject', scopes: ['foo', 'bar'], kid: 'puavo_standalone_2_20250115T095034Z')

      # Load the real JWKS and manually change the KID to match the other key
      jwks = JSON.parse(File.read(CONFIG['oauth2']['key_files']['public_jwks']))
      jwks['keys'][0]['kid'] = 'puavo_standalone_2_20250115T095034Z'

      exception = assert_raises JWT::VerificationError do
        decode_token_jwks(token, jwks)
      end

      assert_equal exception.to_s, 'Signature verification failed'
    end

    it 'multiple keys in a JWKS will work' do
      # Acquire two tokens
      acquire_token('test_client_users2', 'supersecretpassword', ['puavo.read.users'])
      response = JSON.parse last_response.body
      token_a = response['access_token']

      other_key = OpenSSL::PKey.read(File.read(File.join(File.dirname(__FILE__), 'fixtures', 'other_private_key.pem')))
      token_b = sign_token_with_pem(other_key, subject: 'test subject', scopes: ['foo', 'bar'], kid: 'puavo_standalone_2_20250115T095034Z')

      # Combine two different JWKS files
      jwks_a = JSON.parse(File.read(CONFIG['oauth2']['key_files']['public_jwks']))
      jwks_b = JSON.parse(File.read(File.join(File.dirname(__FILE__), 'fixtures', 'other_key_jwks.json')))

      combined_jwks = {
        'keys' => jwks_a['keys'] + jwks_b['keys']
      }

      # The JWKS now contains two keys and thus it must validate both tokens
      decoded_token_a = decode_token_jwks(token_a, combined_jwks)
      decoded_token_b = decode_token_jwks(token_b, combined_jwks)
      assert_equal decoded_token_a['iss'], 'https://api.opinsys.fi'
      assert_equal decoded_token_b['iss'], 'https://api.opinsys.fi'
    end
  end
end

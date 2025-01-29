# OAuth2 access token tests

require_relative './helper'

require 'addressable/uri'
require 'argon2'
require 'jwt'

describe PuavoRest::OAuth2 do
  before(:each) do
    Puavo::Test.clean_up_ldap
    setup_oauth2_database
    setup_ldap_admin_connection()
  end

  def setup_oauth2_database
    # Use the standalone settings
    db_config = CONFIG['oauth2']['client_database']

    db = PG.connect(hostaddr: db_config['host'],
                    port: db_config['port'],
                    dbname: db_config['database'],
                    user: db_config['user'],
                    password: db_config['password'])

    # Delete...
    db.exec("DELETE FROM token_clients WHERE client_id like 'test_client_%';")

    # ...then recreate them. This is wasteful, but I haven't found a way to create
    # these only once at the very start of these tests. There's "before" but it is
    # run before each test.
    array_encoder = PG::TextEncoder::Array.new

    password_hash = Argon2::Password.new(profile: :rfc_9106_low_memory).create('supersecretpassword')
    now = Time.now.utc

    [
      {
        client_id: 'test_client_users_groups',
        scopes: ['puavo.read.users', 'puavo.read.groups'],
        endpoints: ['/v4/users', '/v4/groups'],
      },
      {
        client_id: 'test_client_devices',
        scopes: ['puavo.read.devices'],
        endpoints: ['/v4/devices'],
      },
      {
        client_id: 'test_client_users1',
        scopes: ['puavo.read.users', 'puavo.read.groups'],
        endpoints: ['/v4/users'],
      },
      {
        client_id: 'test_client_users2',
        scopes: ['puavo.read.users'],
        endpoints: ['/v4/users', '/v4/groups'],
      },
    ].each do |client|
      db.exec_params(
        'INSERT INTO token_clients(client_id, client_password, enabled, allowed_scopes, ' \
        'allowed_endpoints, created, modified, password_changed) VALUES ' \
        "($1, $2, true, $3, $4, $5, $6, $7)",
        [client[:client_id], password_hash, array_encoder.encode(client[:scopes]),
        array_encoder.encode(client[:endpoints]), now, now, now]
      )
    end

    db.close
  end

  def acquire_token(client_id, client_password, scopes)
    url = Addressable::URI.parse('/oidc/token')

    url.query_values = {
      'grant_type' => 'client_credentials',
      'scope' => scopes.join(' '),
    }

    basic_authorize client_id, client_password

    post url.to_s
  end

  def fetch_data_with_token(access_token, url, fields)
    url = Addressable::URI.parse(url)

    url.query_values = {
      'fields' => fields
    }

    header 'Host', 'example.puavo.net'
    header 'Authorization', "Bearer #{access_token}"

    get url.to_s
  end

  def decode_token(token, key: OAUTH2_TOKEN_VERIFICATION_PUBLIC_KEY, audience: 'puavo-rest-v4')
    decoded_token = JWT.decode(token, key, true, {
      algorithm: 'ES256',

      verify_iat: true,

      iss: 'https://auth.opinsys.fi',
      verify_iss: true,

      aud: audience,
      verify_aud: true,
    })

    assert_equal decoded_token[1]['typ'], 'at+jwt'
    decoded_token[0]
  end

  it 'ask for something else than client credentials' do
    url = Addressable::URI.parse('/oidc/token')

    url.query_values = {
      'grant_type' => 'spherical_cow',
      'scope' => 'puavo.read.users',
    }

    basic_authorize 'users_client', 'supersecretpassword'

    post url.to_s

    assert_equal last_response.status, 400
    response = JSON.parse last_response.body
    assert_equal response['error'], 'unsupported_grant_type'
    assert_equal response['iss'], 'https://auth.opinsys.fi'
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
      assert_equal response['error'], 'invalid_request'
      assert_equal response['iss'], 'https://auth.opinsys.fi'
    end

    it 'wrong client credentials will fail (1)' do
      acquire_token('foo', 'foo', ['puavo.read.users'])

      assert_equal last_response.status, 400
      response = JSON.parse last_response.body
      assert_equal response['error'], 'unauthorized_client'
      assert_equal response['iss'], 'https://auth.opinsys.fi'
    end

    it 'wrong client credentials will fail (2)' do
      acquire_token('test_client_users_groups', 'wrong password', ['puavo.read.users'])

      assert_equal last_response.status, 400
      response = JSON.parse last_response.body
      assert_equal response['error'], 'unauthorized_client'
      assert_equal response['iss'], 'https://auth.opinsys.fi'
    end

    it 'wrong client credentials will fail (3)' do
      acquire_token('foo', 'supersecretpassword', ['puavo.read.users'])

      assert_equal last_response.status, 400
      response = JSON.parse last_response.body
      assert_equal response['error'], 'unauthorized_client'
      assert_equal response['iss'], 'https://auth.opinsys.fi'
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
      assert_equal response['iss'], 'https://auth.opinsys.fi'
    end

    it 'acquire an access token with smaller scopes' do
      acquire_token('test_client_users_groups', 'supersecretpassword', ['puavo.read.users'])

      assert_equal last_response.status, 200
      response = JSON.parse last_response.body
      assert response['access_token']
      assert_equal response['token_type'], 'Bearer'

      access_token = decode_token(response['access_token'])
      assert_equal access_token['iss'], 'https://auth.opinsys.fi'
      assert_equal access_token['scopes'], 'puavo.read.users'
    end

    it 'excessive scopes are reduced (1)' do
      acquire_token('test_client_users_groups', 'supersecretpassword', ['puavo.read.users', 'puavo.read.groups', 'puavo.read.schools'])

      assert_equal last_response.status, 200
      response = JSON.parse last_response.body
      assert response['access_token']
      assert_equal response['token_type'], 'Bearer'

      access_token = decode_token(response['access_token'])
      assert_equal access_token['iss'], 'https://auth.opinsys.fi'
      assert_equal access_token['scopes'], 'puavo.read.users puavo.read.groups'
    end

    it 'excessive scopes are reduced (2)' do
      acquire_token('test_client_users_groups', 'supersecretpassword', ['puavo.read.users', 'puavo.read.groups', 'puavo.read.schools', 'foo', 'bar'])

      assert_equal last_response.status, 200
      response = JSON.parse last_response.body
      assert response['access_token']
      assert_equal response['token_type'], 'Bearer'

      access_token = decode_token(response['access_token'])
      assert_equal access_token['iss'], 'https://auth.opinsys.fi'
      assert_equal access_token['scopes'], 'puavo.read.users puavo.read.groups'
    end

    it 'try to access something outside of the requested scopes' do
      acquire_token('test_client_devices', 'supersecretpassword', ['puavo.read.devices'])
      response = JSON.parse last_response.body
      access_token = response['access_token']
      decoded_token = decode_token(access_token)
      assert_equal decoded_token['iss'], 'https://auth.opinsys.fi'

      # We have scopes for devices, so try to access groups
      fetch_data_with_token(access_token, '/v4/groups', 'id,abbreviation,name,type,school_id,member_uid')
      assert_equal last_response.status, 401
    end
  end

  it 'acquire a basic access token' do
    acquire_token('test_client_users_groups', 'supersecretpassword', ['puavo.read.users', 'puavo.read.groups'])

    assert_equal last_response.status, 200
    response = JSON.parse last_response.body

    assert response['access_token']
    assert_equal response['token_type'], 'Bearer'

    access_token = decode_token(response['access_token'])
    assert_equal access_token['iss'], 'https://auth.opinsys.fi'
    assert_equal access_token['scopes'], 'puavo.read.users puavo.read.groups'
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

      assert_equal decoded_token['iss'], 'https://auth.opinsys.fi'

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

    it 'retrieve groups data with token authentication' do
      acquire_token('test_client_users_groups', 'supersecretpassword', ['puavo.read.users', 'puavo.read.groups'])
      response = JSON.parse last_response.body
      access_token = response['access_token']
      decoded_token = decode_token(access_token)

      assert_equal decoded_token['iss'], 'https://auth.opinsys.fi'

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
      assert_equal decoded_token['iss'], 'https://auth.opinsys.fi'

      fetch_data_with_token(access_token, '/v4/groups', 'id,abbreviation,name,type,school_id,member_uid')
      assert_equal last_response.status, 403    # invalid endpoint
    end

    it 'cross-configured scopes/endpoints test 2' do
      # This client has access to both endpoints, but scopes only to one of them
      acquire_token('test_client_users2', 'supersecretpassword', ['puavo.read.users'])
      response = JSON.parse last_response.body
      access_token = response['access_token']
      decoded_token = decode_token(access_token)
      assert_equal decoded_token['iss'], 'https://auth.opinsys.fi'

      fetch_data_with_token(access_token, '/v4/groups', 'id,abbreviation,name,type,school_id,member_uid')
      assert_equal last_response.status, 401    # invalid scopes
    end

    it 'expired token will not grant access' do
      # This is a valid access token. But it has expired and won't work anymore.
      expired_token = 'eyJ0eXAiOiJhdCtqd3QiLCJhbGciOiJFUzI1NiJ9.eyJqdGkiOiJiYzk4ZDFlNS01OTUyLTQ3ZT' + \
                      'QtYmI3Yi02OTBlOWE3MjRjOTgiLCJpYXQiOjE3Mzc1NDcyNDQsIm5iZiI6MTczNzU0NzI0NCwiZ' + \
                      'XhwIjoxNzM3NTUwODQ0LCJpc3MiOiJodHRwczovL2F1dGgub3BpbnN5cy5maSIsInN1YiI6InVz' + \
                      'ZXJzX2NsaWVudCIsImF1ZCI6InB1YXZvLXJlc3QtdjQiLCJzY29wZXMiOiJwdWF2by5yZWFkLnV' + \
                      'zZXJzIHB1YXZvLnJlYWQuZ3JvdXBzIiwiY2xpZW50X2lkIjoidXNlcnNfY2xpZW50IiwiYWxsb3' + \
                      'dlZF9lbmRwb2ludHMiOlsiL3Y0L3VzZXJzIl19.Rz_Q7nOFVDtox0QcI9x58It6m849q3EZ9DyH' + \
                      'rLS2wZqTg_9PXKq3dmLCtXdu41bUqlYVv789pMM5SEzT94VvpQ'

      # Ensure the JWT is not valid anymore
      assert_raises JWT::ExpiredSignature do
        JWT.decode(expired_token, OAUTH2_TOKEN_VERIFICATION_PUBLIC_KEY, true, {
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
end

# OAuth2 OpenID Connect login tests

require 'addressable/uri'
require 'jwt'

require_relative 'helper'
require_relative 'oauth2_helpers'

describe PuavoRest::OAuth2 do
  before(:each) do
    Puavo::Test.clean_up_ldap
    setup_ldap_admin_connection()

    @school = School.create(
      cn: 'gryffindor',
      displayName: 'Gryffindor'
    )

    @group = PuavoRest::Group.new(
      name: 'Group 1',
      abbreviation: 'group1',
      school_dn: @school.dn.to_s,
      type: 'teaching group'
    )

    @group.save!

    @user = PuavoRest::User.new(
      first_name: 'Bob',
      last_name: 'Brown',
      username: 'bob.brown',
      roles: ['student'],
      email: 'bob@example.com',
      password: 'secret',
      school_dns: [@school.dn.to_s]
    )

    @user.save!
    @user.teaching_group = @group

    PuavoRest::Organisation.refresh
  end

  # Enables or disables an existing login client
  def enable_login_client(client_id, enabled)
    db = oauth2_client_db()
    db.exec_params('UPDATE login_clients SET enabled = $1 WHERE client_id = $2;', [enabled, client_id])
    db.close
  end

  # Ensures the access token contains the standard fields. The expiration time can be changed if needed.
  def validate_access_token(token, expires_in: 3600)
    assert token.include?('access_token')
    assert token.include?('id_token')

    assert token.include?('token_type')
    assert_equal token['token_type'], 'Bearer'

    assert token.include?('expires_in')
    assert_equal token['expires_in'], expires_in
  end

  describe 'Missing parameters must cause an error' do
    it 'Test missing or empty client_id' do
      # Omitted
      get '/oidc/authorize'
      assert last_response.body.include?('A required parameter "client_id" is missing from the request')
      assert_equal last_response.status, 400

      # Empty
      get '/oidc/authorize?client_id='
      assert last_response.body.include?('A required parameter "client_id" is missing from the request')
      assert_equal last_response.status, 400

      # Just whitespace
      get '/oidc/authorize?client_id=%20%20%20'
      assert last_response.body.include?('A required parameter "client_id" is missing from the request')
      assert_equal last_response.status, 400
    end

    it 'Test missing or empty redirect_uri' do
      # Omitted
      get '/oidc/authorize?client_id=test'
      assert last_response.body.include?('A required parameter "redirect_uri" is missing from the request')
      assert_equal last_response.status, 400

      # Empty
      get '/oidc/authorize?client_id=test&redirect_uri='
      assert last_response.body.include?('A required parameter "redirect_uri" is missing from the request')
      assert_equal last_response.status, 400

      # Just whitespace
      get '/oidc/authorize?client_id=test&redirect_uri=%20%20%20'
      assert last_response.body.include?('A required parameter "redirect_uri" is missing from the request')
      assert_equal last_response.status, 400
    end

    it 'Test missing or empty response_type' do
      # Omitted
      get '/oidc/authorize?client_id=test&redirect_uri=test'
      assert last_response.body.include?('A required parameter "response_type" is missing from the request')
      assert_equal last_response.status, 400

      # Empty
      get '/oidc/authorize?client_id=test&redirect_uri=test&response_type='
      assert last_response.body.include?('A required parameter "response_type" is missing from the request')
      assert_equal last_response.status, 400

      # Just whitespace
      get '/oidc/authorize?client_id=test&redirect_uri=test&response_type=%20%20%20'
      assert last_response.body.include?('A required parameter "response_type" is missing from the request')
      assert_equal last_response.status, 400
    end
  end

  describe 'Test client IDs' do
    before(:context) do
      PuavoRest::Organisation.refresh

      @external_service = ExternalService.new
      @external_service.classes = ['top', 'puavoJWTService']
      @external_service.cn = 'Temporary Service'
      @external_service.puavoServiceDomain = 'temporary.example.com'
      @external_service.puavoServiceSecret = 'secret'
      @external_service.puavoServiceTrusted = false
      @external_service.save!

      activate_organisation_services([@external_service.dn.to_s])

      setup_login_clients([
        {
          client_id: 'test_login_disabled',
          enabled: false,
          puavo_service_dn: @external_service.dn.to_s,
          redirects: ['http://temporary1.example.com'],
          scopes: %w[openid profile]
        },
        {
          client_id: 'test_login_nonexistent_dn',
          enabled: true,
          puavo_service_dn: 'puavoId=999999999,ou=Services,o=puavo',
          redirects: ['http://temporary2.example.com'],
          scopes: %w[openid profile]
        },
        {
          client_id: 'test_login_malformed_dn',
          enabled: true,
          puavo_service_dn: 'foobar',
          redirects: ['http://temporary3.example.com'],
          scopes: %w[openid profile]
        },
      ])
    end

    it 'non-existent client ID' do
      get format_uri('/oidc/authorize', client_id: 'foo', redirect_uri: 'http://temporary1.example.com', response_type: 'code')
      assert last_response.body.include?('Invalid client ID. Login halted.')
      assert_equal last_response.status, 400
    end

    it 'valid client ID, but the client is disabled' do
      get format_uri('/oidc/authorize', client_id: 'test_login_disabled', redirect_uri: 'http://temporary1.example.com', response_type: 'code')
      assert last_response.body.include?('Invalid client ID. Login halted.')
      assert_equal last_response.status, 400
    end

    it 'valid client ID but non-existent Puavo service DN' do
      get format_uri('/oidc/authorize', client_id: 'test_login_nonexistent_dn', redirect_uri: 'http://temporary2.example.com', response_type: 'code')
      assert last_response.body.include?('Invalid client ID. Login halted.')
      assert_equal last_response.status, 400
    end

    it 'valid client ID but malformed Puavo service DN' do
      get format_uri('/oidc/authorize', client_id: 'test_login_malformed_dn', redirect_uri: 'http://temporary3.example.com', response_type: 'code')
      assert last_response.body.include?('Invalid client ID. Login halted.')
      assert_equal last_response.status, 400
    end
  end

  describe 'Invalid response_type and scope error redirect tests' do
    before(:context) do
      PuavoRest::Organisation.refresh

      @external_service = ExternalService.new
      @external_service.classes = ['top', 'puavoJWTService']
      @external_service.cn = 'Service 1'
      @external_service.puavoServiceDomain = 'service.example.com'
      @external_service.puavoServiceSecret = 'secret'
      @external_service.puavoServiceTrusted = false
      @external_service.save!

      activate_organisation_services([@external_service.dn.to_s])

      setup_login_clients([
        {
          client_id: 'test_login_service',
          enabled: true,
          puavo_service_dn: @external_service.dn.to_s,
          redirects: ['http://service.example.com'],
          scopes: %w[openid profile]
        }
      ])
    end

    it 'invalid response_type tests' do
      get format_uri('/oidc/authorize', client_id: 'test_login_service', redirect_uri: 'http://service.example.com', response_type: 'foo')

      # The response_type parameter is checked after the client ID and the redirect URI have been verified, so errors
      # in it will result in a redirect, as specified in RFC 6479 section 4.1.2.1.
      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.host, 'service.example.com'
      assert_equal redirect.query_values['error'], 'invalid_request'
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
    end

    it 'missing "openid" scope results in an error (without state)' do
      get format_uri('/oidc/authorize', client_id: 'test_login_service', redirect_uri: 'http://service.example.com', response_type: 'code', scope: %w[foo bar])

      # This error is also a redirect
      assert last_response.redirect?

      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.host, 'service.example.com'
      assert_equal redirect.query_values['error'], 'invalid_scope'
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
    end

    it 'missing "openid" scope results in an error (with state)' do
      get format_uri('/oidc/authorize', client_id: 'test_login_service', redirect_uri: 'http://service.example.com', response_type: 'code', scope: %w[foo bar], extra: { 'state' => '1234567890' })

      # This error is also a redirect
      assert last_response.redirect?

      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.host, 'service.example.com'
      assert_equal redirect.query_values['error'], 'invalid_scope'
      assert_equal redirect.query_values['state'], '1234567890'
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
    end

    it 'successfull scopes' do
      # This actually reaches the login form
      get format_uri('/oidc/authorize', client_id: 'test_login_service', redirect_uri: 'http://service.example.com', response_type: 'code', scope: 'openid')
      assert_equal last_response.status, 401
      assert last_response.body.include?('Login to service <span>Service 1</span>')
    end
  end

  describe 'Redirect URIs' do
    before(:context) do
      PuavoRest::Organisation.refresh

      @external_service1 = ExternalService.new
      @external_service1.classes = ['top', 'puavoJWTService']
      @external_service1.cn = 'Service 1'
      @external_service1.puavoServiceDomain = 'service1.example.com'
      @external_service1.puavoServiceSecret = 'secret'
      @external_service1.puavoServiceTrusted = false
      @external_service1.save!

      @external_service2 = ExternalService.new
      @external_service2.classes = ['top', 'puavoJWTService']
      @external_service2.cn = 'Service 2'
      @external_service2.puavoServiceDomain = 'service2.example.com'
      @external_service2.puavoServiceSecret = 'secret'
      @external_service2.puavoServiceTrusted = false
      @external_service2.save!

      activate_organisation_services([@external_service1.dn.to_s, @external_service2.dn.to_s])

      setup_login_clients([
        {
          client_id: 'test_login_service1',
          enabled: true,
          puavo_service_dn: @external_service1.dn.to_s,
          redirects: ['http://service1.example.com'],
          scopes: %w[openid profile]
        },
        {
          client_id: 'test_login_service2',
          enabled: true,
          puavo_service_dn: @external_service1.dn.to_s,
          redirects: ['http://service2.example.com', 'http://service2b.example.com'],
          scopes: %w[openid profile]
        },
      ])
    end

    it 'basic redirect  URI test 1' do
      get format_uri('/oidc/authorize', client_id: 'test_login_service1', redirect_uri: 'http://service1.example.com', response_type: 'code', scope: 'openid')
      assert_equal last_response.status, 401
      assert last_response.body.include?('Login to service <span>Service 1</span>')
    end

    it 'basic redirect  URI test 2' do
      # Both redirect URIs must lead to service 2
      get format_uri('/oidc/authorize', client_id: 'test_login_service2', redirect_uri: 'http://service2.example.com', response_type: 'code', scope: 'openid')
      assert_equal last_response.status, 401
      assert last_response.body.include?('Login to service <span>Service 2</span>')

      # unimplemented as of 2025-06-18
      #get format_uri('/oidc/authorize', client_id: 'test_login_service2', redirect_uri: 'http://service2b.example.com', response_type: 'code', scope: 'openid')
      #assert_equal last_response.status, 401
      #assert last_response.body.include?('Login to service <span>Service 2</span>')
    end

    it 'mismatched redirect URI tests' do
      # Try service 2's redirect URIs for service 1
      get format_uri('/oidc/authorize', client_id: 'test_login_service1', redirect_uri: 'http://service2.example.com', response_type: 'code', scope: 'openid')
      assert_equal last_response.status, 400
      assert last_response.body.include?('Invalid redirect URI. Login halted.')

      get format_uri('/oidc/authorize', client_id: 'test_login_service1', redirect_uri: 'http://service2b.example.com', response_type: 'code', scope: 'openid')
      assert_equal last_response.status, 400
      assert last_response.body.include?('Invalid redirect URI. Login halted.')

      # Try service 1's redirect URI for service 2
      get format_uri('/oidc/authorize', client_id: 'test_login_service2', redirect_uri: 'http://service1.example.com', response_type: 'code', scope: 'openid')
      assert_equal last_response.status, 400
      assert last_response.body.include?('Invalid redirect URI. Login halted.')
    end

    it 'invalid redirect URIs' do
      get format_uri('/oidc/authorize', client_id: 'test_login_service1', redirect_uri: 'http://example.com', response_type: 'code', scope: 'openid')
      assert_equal last_response.status, 400
      assert last_response.body.include?('Invalid redirect URI. Login halted.')

      # The redirect URI must be full match, not partial
      get format_uri('/oidc/authorize', client_id: 'test_login_service1', redirect_uri: 'http://service.example.com?foo=bar', response_type: 'code', scope: 'openid')
      assert_equal last_response.status, 400
      assert last_response.body.include?('Invalid redirect URI. Login halted.')

      get format_uri('/oidc/authorize', client_id: 'test_login_service2', redirect_uri: 'http://service3.example.com', response_type: 'code', scope: 'openid')
      assert_equal last_response.status, 400
      assert last_response.body.include?('Invalid redirect URI. Login halted.')

      get format_uri('/oidc/authorize', client_id: 'test_login_service1', redirect_uri: 'asdflsdfkljsdfkljdasf', response_type: 'code', scope: 'openid')
      assert_equal last_response.status, 400
      assert last_response.body.include?('Invalid redirect URI. Login halted.')
    end
  end

  describe 'Login process tests' do
    before(:context) do
      PuavoRest::Organisation.refresh

      @external_service = ExternalService.new
      @external_service.classes = ['top', 'puavoJWTService']
      @external_service.cn = 'The Service'
      @external_service.puavoServiceDomain = 'service.example.com'
      @external_service.puavoServiceSecret = 'secret'
      @external_service.puavoServiceTrusted = false
      @external_service.save!

      activate_organisation_services([@external_service.dn.to_s])

      setup_login_clients([
        {
          client_id: 'test_login_service',
          enabled: true,
          puavo_service_dn: @external_service.dn.to_s,
          redirects: ['http://service.example.com'],
          scopes: %w[openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups]
        }
      ])
    end

    # Basically a "reference" test. Everything is checked.
    it 'Complete succesfull OpenID Connect login and userinfo test' do
      # Step 1: Authorize the user
      get format_uri('/oidc/authorize',
                     client_id: 'test_login_service',
                     redirect_uri: 'http://service.example.com',
                     response_type: 'code',
                     scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                     extra: { 'state' => 'foo', 'nonce' => 'bar' })

      assert_equal last_response.status, 401
      assert last_response.body.include?('Login to service <span>The Service</span>')

      # Ensure we really are in OpenID Connect mode
      assert get_named_form_value('type') == 'oidc'

      # Since "organisation" is not set in the extra params, there must be no organisation name preset
      # on the form
      assert_equal css('input[name="organisation"]').count, 0
      assert_equal css("div.col-orgname").count, 0

      # Simulate a form submission. Forward the hidden form values the backend needs.
      post '/oidc/authorize/post', {
        type: 'oidc',
        request_id: get_named_form_value('request_id'),
        state_key: get_named_form_value('state_key'),
        return_to: get_named_form_value('return_to'),
        username: 'bob.brown@example.puavo.net',
        password: 'secret',
      }

      # Check the response
      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values['state'], 'foo'
      assert_equal redirect.query_values.include?('nonce'), false
      assert_equal redirect.query_values.include?('scope'), false   # the scopes have not changed
      code = redirect.query_values['code']

      # No session cookie must be present
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false

      # Step 2: Acquire the access and ID tokens
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 200
      assert_equal last_response.header['Content-Type'], 'application/json'

      # Check the bearer token
      token = JSON.parse(last_response.body)
      validate_access_token(token)

      # Validate the access token
      access_token = decode_token(token['access_token'], audience: 'puavo-rest-userinfo')

      assert_equal access_token['iss'], 'https://api.opinsys.fi'
      assert_equal access_token['sub'], @user.uuid
      assert_equal access_token['aud'], 'puavo-rest-userinfo'
      assert_equal access_token['scopes'], 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups'
      assert_equal access_token['allowed_endpoints'], ['/oidc/userinfo']
      assert_equal access_token['organisation_domain'], 'example.puavo.net'
      assert_equal access_token['user_dn'], @user.dn.to_s

      # Validate the ID token
      id_token = decode_token(token['id_token'], audience: 'test_login_service')

      assert_equal id_token['iss'], 'https://api.opinsys.fi'
      assert_equal id_token['sub'], @user.uuid
      assert_equal id_token['aud'], 'test_login_service'
      assert_equal id_token['nonce'], 'bar'
      assert_equal id_token['given_name'], @user.first_name
      assert_equal id_token['family_name'], @user.last_name
      assert_equal id_token['name'], "#{@user.first_name} #{@user.last_name}"
      assert_equal id_token['preferred_username'], @user.username
      assert_equal id_token['puavo.uuid'], @user.uuid
      assert_equal id_token['puavo.puavoid'], @user.id
      assert_equal id_token['puavo.roles'], ['student']
      assert_equal id_token['puavo.authenticated_using'], 'username+password'

      assert_equal id_token['puavo.schools'].count, 1
      assert_equal id_token['puavo.schools'][0]['name'], 'Gryffindor'
      assert_equal id_token['puavo.schools'][0]['abbreviation'], 'gryffindor'
      assert_equal id_token['puavo.schools'][0]['puavoid'], @school.id.to_i
      assert_equal id_token['puavo.schools'][0]['primary'], true

      assert_equal id_token['puavo.groups'].count, 1
      assert_equal id_token['puavo.groups'][0]['name'], 'Group 1'
      assert_equal id_token['puavo.groups'][0]['abbreviation'], 'group1'
      assert_equal id_token['puavo.groups'][0]['puavoid'], @group.id.to_i
      assert_equal id_token['puavo.groups'][0]['type'], 'teaching group'
      assert_equal id_token['puavo.groups'][0]['school_abbreviation'], 'gryffindor'

      # Step 3: Call the userinfo endpoint and compare the returned data with the ID token. They must match.
      header 'Host', 'example.puavo.net'
      header 'Authorization', "Bearer #{token['access_token']}"
      get '/oidc/userinfo'

      assert_equal last_response.status, 200
      assert_equal last_response.header['Content-Type'], 'application/json'

      userinfo = JSON.parse(last_response.body)

      assert_equal userinfo['sub'], @user.uuid
      assert_equal userinfo['given_name'], id_token['given_name']
      assert_equal userinfo['family_name'], id_token['family_name']
      assert_equal userinfo['name'], id_token['name']
      assert_equal userinfo['preferred_username'], id_token['preferred_username']
      assert_equal userinfo['puavo.uuid'], id_token['puavo.uuid']
      assert_equal userinfo['puavo.puavoid'], id_token['puavo.puavoid']
      assert_equal userinfo['puavo.roles'], id_token['puavo.roles']

      # This must be nil because the authentication method is only known during the login
      assert_nil userinfo['puavo.authenticated_using']
    end

    it 'Wrong key must not validate the tokens' do
      # Step 1: Authorize the user
      get format_uri('/oidc/authorize',
                     client_id: 'test_login_service',
                     redirect_uri: 'http://service.example.com',
                     response_type: 'code',
                     scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                     extra: { 'state' => 'foo', 'nonce' => 'bar' })

      assert_equal last_response.status, 401
      assert last_response.body.include?('Login to service <span>The Service</span>')
      assert get_named_form_value('type') == 'oidc'
      assert_equal css('input[name="organisation"]').count, 0
      assert_equal css("div.col-orgname").count, 0

      post '/oidc/authorize/post', {
        type: 'oidc',
        request_id: get_named_form_value('request_id'),
        state_key: get_named_form_value('state_key'),
        return_to: get_named_form_value('return_to'),
        username: 'bob.brown@example.puavo.net',
        password: 'secret',
      }

      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values['state'], 'foo'
      assert_equal redirect.query_values.include?('nonce'), false
      assert_equal redirect.query_values.include?('scope'), false   # the scopes have not changed
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false
      code = redirect.query_values['code']

      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 200
      assert_equal last_response.header['Content-Type'], 'application/json'

      # Check the bearer token
      token = JSON.parse(last_response.body)
      validate_access_token(token)

      # Ensure the access and ID tokens cannot be validated using another key

      # The "other key" is actually a real, working public key I generated for this test.
      # It's just not the key we need to validate the generated token.
      other_key = OpenSSL::PKey.read(File.read(File.join(File.dirname(__FILE__), 'fixtures', 'other_public_key.pem')))

      exception = assert_raises JWT::VerificationError do
        decode_token(token['access_token'], key: other_key)
      end

      assert_equal exception.to_s, 'Signature verification failed'

      exception = assert_raises JWT::VerificationError do
        decode_token(token['id_token'], key: other_key, audience: 'test_login_service')
      end

      assert_equal exception.to_s, 'Signature verification failed'
    end

    # Specify the domain in the username anyway
    it 'Login with pre-set organisation (part 1)' do
      # Step 1: Authorize the user
      get format_uri('/oidc/authorize',
                     client_id: 'test_login_service',
                     redirect_uri: 'http://service.example.com',
                     response_type: 'code',
                     scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                     extra: { 'state' => 'foo', 'nonce' => 'bar', 'organisation' => 'example.puavo.net' })

      assert_equal last_response.status, 401
      assert last_response.body.include?('Login to service <span>The Service</span>')
      assert get_named_form_value('type') == 'oidc'

      # These two elements must be present
      assert css('input[name="organisation"]')
      assert css("div.col-orgname")

      assert_equal get_named_form_value('organisation'), 'example.puavo.net'
      assert_equal css("div.col-orgname").children.first.text, '@example.puavo.net'

      post '/oidc/authorize/post', {
        type: 'oidc',
        request_id: get_named_form_value('request_id'),
        state_key: get_named_form_value('state_key'),
        organisation: get_named_form_value('organisation'),
        return_to: get_named_form_value('return_to'),
        username: 'bob.brown@example.puavo.net',    # the domain is redundant, but it must work
        password: 'secret',
      }

      # Check the response
      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values['state'], 'foo'
      assert_equal redirect.query_values.include?('nonce'), false
      assert_equal redirect.query_values.include?('scope'), false   # the scopes have not changed
      code = redirect.query_values['code']

      # No session cookie must be present
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false

      # Step 2: Acquire the access and ID tokens
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 200
      assert_equal last_response.header['Content-Type'], 'application/json'

      # Check the bearer token
      token = JSON.parse(last_response.body)
      validate_access_token(token)

      # Validate the access token
      access_token = decode_token(token['access_token'], audience: 'puavo-rest-userinfo')

      assert_equal access_token['iss'], 'https://api.opinsys.fi'
      assert_equal access_token['sub'], @user.uuid
      assert_equal access_token['aud'], 'puavo-rest-userinfo'
      assert_equal access_token['scopes'], 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups'
      assert_equal access_token['allowed_endpoints'], ['/oidc/userinfo']
      assert_equal access_token['organisation_domain'], 'example.puavo.net'
      assert_equal access_token['user_dn'], @user.dn.to_s

      # Validate the ID token
      id_token = decode_token(token['id_token'], audience: 'test_login_service')

      assert_equal id_token['iss'], 'https://api.opinsys.fi'
      assert_equal id_token['sub'], @user.uuid
      assert_equal id_token['aud'], 'test_login_service'
      assert_equal id_token['nonce'], 'bar'
      assert_equal id_token['given_name'], @user.first_name
      assert_equal id_token['family_name'], @user.last_name
      assert_equal id_token['name'], "#{@user.first_name} #{@user.last_name}"
      assert_equal id_token['preferred_username'], @user.username
      assert_equal id_token['puavo.uuid'], @user.uuid
      assert_equal id_token['puavo.puavoid'], @user.id
      assert_equal id_token['puavo.roles'], ['student']
      assert_equal id_token['puavo.authenticated_using'], 'username+password'
      assert_equal id_token['puavo.schools'].count, 1
      assert_equal id_token['puavo.groups'].count, 1
    end

    # Test with just the username, without the domain
    it 'Login with pre-set organisation (part 2)' do
      # Step 1: Authorize the user
      get format_uri('/oidc/authorize',
                     client_id: 'test_login_service',
                     redirect_uri: 'http://service.example.com',
                     response_type: 'code',
                     scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                     extra: { 'state' => 'foo', 'nonce' => 'bar', 'organisation' => 'example.puavo.net' })

      assert_equal last_response.status, 401
      assert last_response.body.include?('Login to service <span>The Service</span>')
      assert get_named_form_value('type') == 'oidc'

      # These two elements must be present
      assert css('input[name="organisation"]')
      assert css("div.col-orgname")

      assert_equal get_named_form_value('organisation'), 'example.puavo.net'
      assert_equal css("div.col-orgname").children.first.text, '@example.puavo.net'

      post '/oidc/authorize/post', {
        type: 'oidc',
        request_id: get_named_form_value('request_id'),
        state_key: get_named_form_value('state_key'),
        organisation: get_named_form_value('organisation'),
        return_to: get_named_form_value('return_to'),
        username: 'bob.brown',      # no domain here
        password: 'secret',
      }

      # Check the response
      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values['state'], 'foo'
      assert_equal redirect.query_values.include?('nonce'), false
      assert_equal redirect.query_values.include?('scope'), false   # the scopes have not changed
      code = redirect.query_values['code']

      # No session cookie must be present
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false

      # Step 2: Acquire the access and ID tokens
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 200
      assert_equal last_response.header['Content-Type'], 'application/json'

      # Check the bearer token
      token = JSON.parse(last_response.body)
      validate_access_token(token)

      # Validate the access token
      access_token = decode_token(token['access_token'], audience: 'puavo-rest-userinfo')

      assert_equal access_token['iss'], 'https://api.opinsys.fi'
      assert_equal access_token['sub'], @user.uuid
      assert_equal access_token['aud'], 'puavo-rest-userinfo'
      assert_equal access_token['scopes'], 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups'
      assert_equal access_token['allowed_endpoints'], ['/oidc/userinfo']
      assert_equal access_token['organisation_domain'], 'example.puavo.net'
      assert_equal access_token['user_dn'], @user.dn.to_s

      # Validate the ID token
      id_token = decode_token(token['id_token'], audience: 'test_login_service')

      assert_equal id_token['iss'], 'https://api.opinsys.fi'
      assert_equal id_token['sub'], @user.uuid
      assert_equal id_token['aud'], 'test_login_service'
      assert_equal id_token['nonce'], 'bar'
      assert_equal id_token['given_name'], @user.first_name
      assert_equal id_token['family_name'], @user.last_name
      assert_equal id_token['name'], "#{@user.first_name} #{@user.last_name}"
      assert_equal id_token['preferred_username'], @user.username
      assert_equal id_token['puavo.uuid'], @user.uuid
      assert_equal id_token['puavo.puavoid'], @user.id
      assert_equal id_token['puavo.roles'], ['student']
      assert_equal id_token['puavo.authenticated_using'], 'username+password'
      assert_equal id_token['puavo.schools'].count, 1
      assert_equal id_token['puavo.groups'].count, 1
    end

    # This time the pre-set organisation differs from the organisation in the username
    it 'Login with pre-set organisation (part 3)' do
      get format_uri('/oidc/authorize',
                     client_id: 'test_login_service',
                     redirect_uri: 'http://service.example.com',
                     response_type: 'code',
                     scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                     extra: { 'state' => 'foo', 'nonce' => 'bar', 'organisation' => 'example.puavo.net' })

      assert_equal last_response.status, 401
      assert last_response.body.include?('Login to service <span>The Service</span>')
      assert get_named_form_value('type') == 'oidc'

      assert css('input[name="organisation"]')
      assert css("div.col-orgname")
      assert_equal get_named_form_value('organisation'), 'example.puavo.net'
      assert_equal css("div.col-orgname").children.first.text, '@example.puavo.net'

      post '/oidc/authorize/post', {
        type: 'oidc',
        request_id: get_named_form_value('request_id'),
        state_key: get_named_form_value('state_key'),
        organisation: get_named_form_value('organisation'),
        return_to: get_named_form_value('return_to'),
        username: 'bob.brown@foo.puavo.net',    # different domain
        password: 'secret',
      }

      # Check the response, we're back in the login form with an error message
      assert_equal last_response.status, 401
      assert last_response.body.include?('Login to service <span>The Service</span>')
      assert get_named_form_value('type') == 'oidc'
      assert_equal css("p#error").text, 'Invalid username'
    end

    # Completely omit all organisation information
    it 'Login without any organisation domain' do
      get format_uri('/oidc/authorize',
                     client_id: 'test_login_service',
                     redirect_uri: 'http://service.example.com',
                     response_type: 'code',
                     scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                     extra: { 'state' => 'foo', 'nonce' => 'bar' })

      assert_equal last_response.status, 401
      assert last_response.body.include?('Login to service <span>The Service</span>')
      assert get_named_form_value('type') == 'oidc'
      assert_equal css('input[name="organisation"]').count, 0
      assert_equal css("div.col-orgname").count, 0

      post '/oidc/authorize/post', {
        type: 'oidc',
        request_id: get_named_form_value('request_id'),
        state_key: get_named_form_value('state_key'),
        return_to: get_named_form_value('return_to'),
        username: 'bob.brown',
        password: 'secret',
      }

      # Check the response, we're back in the login form with an error message
      assert_equal last_response.status, 401
      assert last_response.body.include?('Login to service <span>The Service</span>')
      assert get_named_form_value('type') == 'oidc'
      assert_equal css("p#error").text, 'Organisation is missing from the username. Use username@organisation.opinsys.fi format.'
    end

    it 'Client gets disabled half-way the process' do
      # Step 1: Authorize the user
      get format_uri('/oidc/authorize',
                     client_id: 'test_login_service',
                     redirect_uri: 'http://service.example.com',
                     response_type: 'code',
                     scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                     extra: { 'state' => 'foo', 'nonce' => 'bar' })

      assert_equal last_response.status, 401
      assert last_response.body.include?('Login to service <span>The Service</span>')
      assert get_named_form_value('type') == 'oidc'

      post '/oidc/authorize/post', {
        type: 'oidc',
        request_id: get_named_form_value('request_id'),
        state_key: get_named_form_value('state_key'),
        return_to: get_named_form_value('return_to'),
        username: 'bob.brown@example.puavo.net',
        password: 'secret',
      }

      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values['state'], 'foo'
      assert_equal redirect.query_values.include?('nonce'), false
      assert_equal redirect.query_values.include?('scope'), false   # the scopes have not changed
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false
      code = redirect.query_values['code']

      # Disable the client
      enable_login_client('test_login_service', false)

      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 400
      assert_equal last_response.header['Content-Type'], 'application/json'
      error = JSON.parse(last_response.body)
      assert_equal error['error'], 'unauthorized_client'
    end

    it 'stage 1 "type" parameter validation' do
      params = go_to_login_form(client_id: 'test_login_service',
                                redirect_uri: 'http://service.example.com',
                                scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                                service_title: 'Login to service <span>The Service</span>')

      # Intentionally wrong mode (JWT)
      post '/oidc/authorize/post', {
        type: 'jwt',
        request_id: params[:request_id],
        state_key: params[:state_key],
        return_to: params[:return_to],
        username: 'bob.brown@example.puavo.net',
        password: 'secret',
      }

      assert_equal last_response.status, 400
      assert css('p#error').text.include?('System error, login halted. Please contact support and give them this code:')
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false
    end

    it 'stage 1 "state_key" parameter validation' do
      params = go_to_login_form(client_id: 'test_login_service',
                                redirect_uri: 'http://service.example.com',
                                scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                                service_title: 'Login to service <span>The Service</span>')

      # Intentionally wrong state key (so the login state cannot be found in Redis)
      post '/oidc/authorize/post', {
        type: 'oidc',
        request_id: params[:request_id],
        state_key: 'foobar',
        return_to: params[:return_to],
        username: 'bob.brown@example.puavo.net',
        password: 'secret',
      }

      assert_equal last_response.status, 400
      assert css('p#error').text.include?('System error, login halted. Please contact support and give them this code:')
    end

    it 'stage 1 "return_to" parameter validation' do
      params = go_to_login_form(client_id: 'test_login_service',
                                redirect_uri: 'http://service.example.com',
                                scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                                service_title: 'Login to service <span>The Service</span>')

      # Use a different return_to address, so the form submission validation will fail
      post '/oidc/authorize/post', {
        type: 'oidc',
        request_id: params[:request_id],
        state_key: params[:state_key],
        return_to: 'hölökyn kölökyn',
        username: 'bob.brown@example.puavo.net',
        password: 'secret',
      }

      assert_equal last_response.status, 400
      assert css('p#error').text.include?('Inconsistency between stored state and form data. Login halted.')
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false
    end

    it 'stage 2 "grant_type" validation' do
      params = go_to_login_form(client_id: 'test_login_service',
                                redirect_uri: 'http://service.example.com',
                                scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                                service_title: 'Login to service <span>The Service</span>')

      do_login(username: 'bob.brown@example.puavo.net', password: 'secret', params: params)

      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values.include?('state'), false
      assert_equal redirect.query_values.include?('scope'), false   # the scopes have not changed
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false
      code = redirect.query_values['code']

      post '/oidc/token', {
        grant_type: 'foo',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 400
      assert_equal last_response.header['Content-Type'], 'application/json'

      body = JSON.parse(last_response.body)
      assert_equal body['error'], 'unsupported_grant_type'
      assert_equal body['iss'], 'https://api.opinsys.fi'
    end

    it 'stage 2 "client_id" validation (part 1)' do
      params = go_to_login_form(client_id: 'test_login_service',
                                redirect_uri: 'http://service.example.com',
                                scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                                service_title: 'Login to service <span>The Service</span>')

      do_login(username: 'bob.brown@example.puavo.net', password: 'secret', params: params)

      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values.include?('state'), false
      assert_equal redirect.query_values.include?('scope'), false   # the scopes have not changed
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false
      code = redirect.query_values['code']

      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'quux',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 400
      assert_equal last_response.header['Content-Type'], 'application/json'

      body = JSON.parse(last_response.body)
      assert_equal body['error'], 'unauthorized_client'
      assert_equal body['iss'], 'https://api.opinsys.fi'

      # Try a valid request immediately afterwards. This must fail, because 'code' was valid in the
      # previous request so the state was immediately purged even if the request failed.
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 400
      assert_equal last_response.header['Content-Type'], 'application/json'

      body = JSON.parse(last_response.body)
      assert_equal body['error'], 'invalid_request'
      assert_equal body['iss'], 'https://api.opinsys.fi'
    end

    it 'stage 2 "client_id" validation (part 2)' do
      params = go_to_login_form(client_id: 'test_login_service',
                                redirect_uri: 'http://service.example.com',
                                scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                                service_title: 'Login to service <span>The Service</span>')

      do_login(username: 'bob.brown@example.puavo.net', password: 'secret', params: params)

      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values.include?('state'), false
      assert_equal redirect.query_values.include?('scope'), false   # the scopes have not changed
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false
      code = redirect.query_values['code']

      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'A' * 65536,
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 400
      assert_equal last_response.header['Content-Type'], 'application/json'

      body = JSON.parse(last_response.body)
      assert_equal body['error'], 'unauthorized_client'
      assert_equal body['iss'], 'https://api.opinsys.fi'

      # Ensure the state is invalidated
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 400
      assert_equal last_response.header['Content-Type'], 'application/json'

      body = JSON.parse(last_response.body)
      assert_equal body['error'], 'invalid_request'
      assert_equal body['iss'], 'https://api.opinsys.fi'
    end

    it 'stage 2 "client_id" validation (part 3)' do
      params = go_to_login_form(client_id: 'test_login_service',
                                redirect_uri: 'http://service.example.com',
                                scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                                service_title: 'Login to service <span>The Service</span>')

      do_login(username: 'bob.brown@example.puavo.net', password: 'secret', params: params)

      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values.include?('state'), false
      assert_equal redirect.query_values.include?('scope'), false   # the scopes have not changed
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false
      code = redirect.query_values['code']

      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 400
      assert_equal last_response.header['Content-Type'], 'application/json'

      body = JSON.parse(last_response.body)
      assert_equal body['error'], 'unauthorized_client'
      assert_equal body['iss'], 'https://api.opinsys.fi'

      # Ensure the state is invalidated
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 400
      assert_equal last_response.header['Content-Type'], 'application/json'

      body = JSON.parse(last_response.body)
      assert_equal body['error'], 'invalid_request'
      assert_equal body['iss'], 'https://api.opinsys.fi'
    end

    it 'stage 2 "redirect_uri" validation (part 1)' do
      params = go_to_login_form(client_id: 'test_login_service',
                                redirect_uri: 'http://service.example.com',
                                scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                                service_title: 'Login to service <span>The Service</span>')

      do_login(username: 'bob.brown@example.puavo.net', password: 'secret', params: params)

      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values.include?('state'), false
      assert_equal redirect.query_values.include?('scope'), false   # the scopes have not changed
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false
      code = redirect.query_values['code']

      # Use a different redirect URI
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://palvelu.example.com',
        code: code
      }

      assert_equal last_response.status, 400
      assert_equal last_response.header['Content-Type'], 'application/json'

      body = JSON.parse(last_response.body)
      assert_equal body['error'], 'invalid_request'
      assert_equal body['iss'], 'https://api.opinsys.fi'

      # Ensure the state is invalidated
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 400
      assert_equal last_response.header['Content-Type'], 'application/json'

      body = JSON.parse(last_response.body)
      assert_equal body['error'], 'invalid_request'
      assert_equal body['iss'], 'https://api.opinsys.fi'
    end

    it 'stage 2 "redirect_uri" validation (part 2)' do
      params = go_to_login_form(client_id: 'test_login_service',
                                redirect_uri: 'http://service.example.com',
                                scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                                service_title: 'Login to service <span>The Service</span>')

      do_login(username: 'bob.brown@example.puavo.net', password: 'secret', params: params)

      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values.include?('state'), false
      assert_equal redirect.query_values.include?('scope'), false   # the scopes have not changed
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false
      code = redirect.query_values['code']

      # Completely omit the URI
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        code: code
      }

      assert_equal last_response.status, 400
      assert_equal last_response.header['Content-Type'], 'application/json'

      body = JSON.parse(last_response.body)
      assert_equal body['error'], 'invalid_request'
      assert_equal body['iss'], 'https://api.opinsys.fi'

      # Ensure the state is invalidated
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 400
      assert_equal last_response.header['Content-Type'], 'application/json'

      body = JSON.parse(last_response.body)
      assert_equal body['error'], 'invalid_request'
      assert_equal body['iss'], 'https://api.opinsys.fi'
    end

    it 'stage 2 "redirect_uri" validation (part 3)' do
      params = go_to_login_form(client_id: 'test_login_service',
                                redirect_uri: 'http://service.example.com',
                                scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                                service_title: 'Login to service <span>The Service</span>')

      do_login(username: 'bob.brown@example.puavo.net', password: 'secret', params: params)

      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values.include?('state'), false
      assert_equal redirect.query_values.include?('scope'), false   # the scopes have not changed
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false
      code = redirect.query_values['code']

      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        code: code
      }

      assert_equal last_response.status, 400
      assert_equal last_response.header['Content-Type'], 'application/json'

      body = JSON.parse(last_response.body)
      assert_equal body['error'], 'invalid_request'
      assert_equal body['iss'], 'https://api.opinsys.fi'

      # Ensure the state is invalidated
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'A' * 65536,
        code: code
      }

      assert_equal last_response.status, 400
      assert_equal last_response.header['Content-Type'], 'application/json'

      body = JSON.parse(last_response.body)
      assert_equal body['error'], 'invalid_request'
      assert_equal body['iss'], 'https://api.opinsys.fi'
    end

    it 'stage 2 "redirect_uri" validation (part 4)' do
      params = go_to_login_form(client_id: 'test_login_service',
                                redirect_uri: 'http://service.example.com',
                                scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                                service_title: 'Login to service <span>The Service</span>')

      do_login(username: 'bob.brown@example.puavo.net', password: 'secret', params: params)

      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values.include?('state'), false
      assert_equal redirect.query_values.include?('scope'), false   # the scopes have not changed
      code = redirect.query_values['code']

      # nil URI
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: nil,
        code: code
      }

      assert_equal last_response.status, 400
      assert_equal last_response.header['Content-Type'], 'application/json'

      body = JSON.parse(last_response.body)
      assert_equal body['error'], 'invalid_request'
      assert_equal body['iss'], 'https://api.opinsys.fi'

      # Ensure the state is invalidated
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 400
      assert_equal last_response.header['Content-Type'], 'application/json'

      body = JSON.parse(last_response.body)
      assert_equal body['error'], 'invalid_request'
      assert_equal body['iss'], 'https://api.opinsys.fi'
    end

    it 'stage 2 "client_secret" validation (part 1)' do
      params = go_to_login_form(client_id: 'test_login_service',
                                redirect_uri: 'http://service.example.com',
                                scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                                service_title: 'Login to service <span>The Service</span>')

      do_login(username: 'bob.brown@example.puavo.net', password: 'secret', params: params)

      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values.include?('state'), false
      assert_equal redirect.query_values.include?('scope'), false   # the scopes have not changed
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false
      code = redirect.query_values['code']

      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: 'quux',
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 400
      assert_equal last_response.header['Content-Type'], 'application/json'

      body = JSON.parse(last_response.body)
      assert_equal body['error'], 'unauthorized_client'
      assert_equal body['iss'], 'https://api.opinsys.fi'

      # Ensure the state is invalidated
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 400
      assert_equal last_response.header['Content-Type'], 'application/json'

      body = JSON.parse(last_response.body)
      assert_equal body['error'], 'invalid_request'
      assert_equal body['iss'], 'https://api.opinsys.fi'
    end

    it 'stage 2 "client_secret" validation (part 2)' do
      params = go_to_login_form(client_id: 'test_login_service',
                                redirect_uri: 'http://service.example.com',
                                scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                                service_title: 'Login to service <span>The Service</span>')

      do_login(username: 'bob.brown@example.puavo.net', password: 'secret', params: params)

      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values.include?('state'), false
      assert_equal redirect.query_values.include?('scope'), false   # the scopes have not changed
      code = redirect.query_values['code']

      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 400
      assert_equal last_response.header['Content-Type'], 'application/json'

      body = JSON.parse(last_response.body)
      assert_equal body['error'], 'unauthorized_client'
      assert_equal body['iss'], 'https://api.opinsys.fi'

      # Ensure the state is invalidated
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 400
      assert_equal last_response.header['Content-Type'], 'application/json'

      body = JSON.parse(last_response.body)
      assert_equal body['error'], 'invalid_request'
      assert_equal body['iss'], 'https://api.opinsys.fi'
    end

    it 'stage 2 "code" validation' do
      params = go_to_login_form(client_id: 'test_login_service',
                                redirect_uri: 'http://service.example.com',
                                scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                                service_title: 'Login to service <span>The Service</span>')

      do_login(username: 'bob.brown@example.puavo.net', password: 'secret', params: params)

      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values.include?('state'), false
      assert_equal redirect.query_values.include?('scope'), false   # the scopes have not changed
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false
      code = redirect.query_values['code']

      # Omit the "code" parameter on purpose
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        redirect_uri: 'http://service.example.com',
      }

      assert_equal last_response.status, 400
      assert_equal last_response.header['Content-Type'], 'application/json'

      body = JSON.parse(last_response.body)
      assert_equal body['error'], 'invalid_request'
      assert_equal body['iss'], 'https://api.opinsys.fi'

      # Use nil code
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        redirect_uri: 'http://service.example.com',
        code: nil
      }

      assert_equal last_response.status, 400
      assert_equal last_response.header['Content-Type'], 'application/json'

      body = JSON.parse(last_response.body)
      assert_equal body['error'], 'invalid_request'
      assert_equal body['iss'], 'https://api.opinsys.fi'

      # Use invalid code
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        redirect_uri: 'http://service.example.com',
        code: 'foofoofoo'
      }

      assert_equal last_response.status, 400
      assert_equal last_response.header['Content-Type'], 'application/json'

      body = JSON.parse(last_response.body)
      assert_equal body['error'], 'invalid_request'
      assert_equal body['iss'], 'https://api.opinsys.fi'

      # Now the request should work, as the previous request could not remove the state
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 200
      assert_equal last_response.header['Content-Type'], 'application/json'

      token = JSON.parse(last_response.body)
      assert_equal body['iss'], 'https://api.opinsys.fi'
      assert token.include?('access_token')
      assert token.include?('id_token')
      assert token.include?('token_type')
      assert_equal token['token_type'], 'Bearer'
    end

    it 'fewer scopes' do
      params = go_to_login_form(client_id: 'test_login_service',
                                redirect_uri: 'http://service.example.com',
                                scope: 'openid profile',
                                service_title: 'Login to service <span>The Service</span>')

      post '/oidc/authorize/post', {
        type: 'oidc',
        request_id: params[:request_id],
        state_key: params[:state_key],
        return_to: params[:return_to],
        username: 'bob.brown@example.puavo.net',
        password: 'secret',
      }

      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values.include?('state'), false
      code = redirect.query_values['code']

      # Since the scopes don't change, the 'scope' parameter must not be present
      assert_equal redirect.query_values.include?('scope'), false

      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 200

      # Check the returned scopes
      token = JSON.parse(last_response.body)
      access_token = decode_token(token['access_token'], audience: 'puavo-rest-userinfo')
      assert_equal access_token['scopes'], 'openid profile'

      # Check that the ID token does not contain unwanted data
      id_token = decode_token(token['id_token'], audience: 'test_login_service')
      assert_equal id_token.include?('puavo.schools'), false
      assert_equal id_token.include?('puavo.groups'), false
    end

    it 'more scopes' do
      params = go_to_login_form(client_id: 'test_login_service',
                                redirect_uri: 'http://service.example.com',
                                scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups puavo.read.userinfo.organisation puavo.read.userinfo.admin puavo.read.userinfo.security',
                                service_title: 'Login to service <span>The Service</span>')

      post '/oidc/authorize/post', {
        type: 'oidc',
        request_id: params[:request_id],
        state_key: params[:state_key],
        return_to: params[:return_to],
        username: 'bob.brown@example.puavo.net',
        password: 'secret',
      }

      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values.include?('state'), false
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false
      code = redirect.query_values['code']

      # The extra scopes must not be present. The 'scope' parameter is present, since the scopes changed.
      scopes = redirect.query_values['scope'].split
      assert_equal scopes.include?('puavo.read.userinfo.organisation'), false
      assert_equal scopes.include?('puavo.read.userinfo.admin'), false
      assert_equal scopes.include?('puavo.read.userinfo.security'), false

      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 200

      # Check the returned scopes. No extra scopes must be present.
      token = JSON.parse(last_response.body)
      access_token = decode_token(token['access_token'], audience: 'puavo-rest-userinfo')
      assert_equal access_token['scopes'], 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups'

      # Check the ID token contents
      id_token = decode_token(token['id_token'], audience: 'test_login_service')
      assert_equal id_token.include?('puavo.schools'), true
      assert_equal id_token.include?('puavo.groups'), true
      assert_equal id_token.include?('puavo.organisation'), false
      assert_equal id_token.include?('puavo.is_organisation_owner'), false
      assert_equal id_token.include?('puavo.admin_in_schools'), false
      assert_equal id_token.include?('puavo.mfa_enabled'), false
      assert_equal id_token.include?('puavo.super_owner'), false
    end

    it 'invalid scopes' do
      params = go_to_login_form(client_id: 'test_login_service',
                                redirect_uri: 'http://service.example.com',
                                scope: 'openid foo bar baz quux',
                                service_title: 'Login to service <span>The Service</span>',
                                extra: { 'state' => 'foo', 'nonce' => 'bar' })

      post '/oidc/authorize/post', {
        type: 'oidc',
        request_id: params[:request_id],
        state_key: params[:state_key],
        return_to: params[:return_to],
        username: 'bob.brown@example.puavo.net',
        password: 'secret',
      }

      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values.include?('state'), true
      assert_equal redirect.query_values.include?('nonce'), false
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false
      code = redirect.query_values['code']

      # The invalid scopes must not be present
      scopes = redirect.query_values['scope'].split
      assert_equal scopes.include?('openid'), true
      assert_equal scopes.include?('foo'), false
      assert_equal scopes.include?('bar'), false
      assert_equal scopes.include?('baz'), false
      assert_equal scopes.include?('quux'), false

      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 200

      # Check the returned scopes. No extra scopes must be present.
      token = JSON.parse(last_response.body)
      access_token = decode_token(token['access_token'], audience: 'puavo-rest-userinfo')
      assert_equal access_token['scopes'], 'openid'

      # Check the ID token contents
      id_token = decode_token(token['id_token'], audience: 'test_login_service')

      %w[given_name family_name name preferred_username puavo.uuid puavo.puavoid puavo.roles puavo.authenticated_using puavo.schools puavo.groups].each do |claim|
        assert_equal id_token.include?(claim), false
      end

      assert_equal id_token.include?('nonce'), true
      assert_equal id_token['nonce'], 'bar'
    end

    it 'different scopes at different points of the login process' do
      params = go_to_login_form(client_id: 'test_login_service',
                                redirect_uri: 'http://service.example.com',
                                scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                                service_title: 'Login to service <span>The Service</span>')

      post '/oidc/authorize/post', {
        type: 'oidc',
        request_id: params[:request_id],
        state_key: params[:state_key],
        return_to: params[:return_to],
        username: 'bob.brown@example.puavo.net',
        password: 'secret',
      }

      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values.include?('state'), false
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false
      code = redirect.query_values['code']

      # Since the scopes don't change, the 'scope' parameter must not be present
      assert_equal redirect.query_values.include?('scope'), false

      # Use different scopes in the authorization code request. Since we ignore the scopes in this request,
      # the returned tokens will contain scopes and data from the original request.
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://service.example.com',
        scope: 'foo bar',
        code: code
      }

      assert_equal last_response.status, 200

      token = JSON.parse(last_response.body)
      access_token = decode_token(token['access_token'], audience: 'puavo-rest-userinfo')
      assert_equal access_token['scopes'], 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups'

      id_token = decode_token(token['id_token'], audience: 'test_login_service')
      assert_equal id_token.include?('puavo.schools'), true
      assert_equal id_token.include?('puavo.groups'), true
    end
  end

  describe 'test SSO sessions with OpenID Connect' do
    before(:context) do
      PuavoRest::Organisation.refresh

      @external_service = ExternalService.new
      @external_service.classes = ['top', 'puavoJWTService']
      @external_service.cn = 'Normal service'
      @external_service.puavoServiceDomain = 'normal_service.example.com'
      @external_service.puavoServiceSecret = 'secret'
      @external_service.puavoServiceTrusted = false
      @external_service.save!

      @external_service2 = ExternalService.new
      @external_service2.classes = ['top', 'puavoJWTService']
      @external_service2.cn = 'Service with SSO sessions'
      @external_service2.puavoServiceDomain = 'session_test.example.com'
      @external_service2.puavoServiceSecret = 'password'
      @external_service2.puavoServiceTrusted = false
      @external_service2.save!

      activate_organisation_services([@external_service.dn.to_s, @external_service2.dn.to_s])

      setup_login_clients([
        {
          client_id: 'test_login_service',
          enabled: true,
          puavo_service_dn: @external_service.dn.to_s,
          redirects: ['http://normal_service.example.com'],
          scopes: %w[openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups]
        },
        {
          client_id: 'test_login_service_session',
          enabled: true,
          puavo_service_dn: @external_service2.dn.to_s,
          redirects: ['http://session_test.example.com'],
          scopes: %w[openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups]
        }
      ])
    end

    # Like the basic OpenID Connect login test, this is a reference OpenID Connect login with sessions test
    it 'a basic SSO session test' do
      clear_cookies

      # Part 1: Acquire data normally using OpenID Connect. This is almost identical to the basic OIDC login test.
      get format_uri('/oidc/authorize',
                     client_id: 'test_login_service_session',
                     redirect_uri: 'http://session_test.example.com',
                     response_type: 'code',
                     scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                     extra: { 'state' => 'baz', 'nonce' => 'quux' })

      assert_equal last_response.status, 401
      assert last_response.body.include?('Login to service <span>Service with SSO sessions</span>')
      assert get_named_form_value('type') == 'oidc'

      post '/oidc/authorize/post', {
        type: 'oidc',
        request_id: get_named_form_value('request_id'),
        state_key: get_named_form_value('state_key'),
        return_to: get_named_form_value('return_to'),
        username: 'bob.brown@example.puavo.net',
        password: 'secret',
      }

      # Check the response
      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values['state'], 'baz'
      assert_equal redirect.query_values.include?('nonce'), false
      assert_equal redirect.query_values.include?('scope'), false   # the scopes have not changed
      code = redirect.query_values['code']

      # Must have a session cookie
      assert_equal last_response.headers.include?('Location'), true
      assert_equal last_response.headers.include?('Set-Cookie'), true
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), true
      session_key = last_response.cookies[PUAVO_SSO_SESSION_KEY][0]

      # Step 2: Acquire the access and ID tokens
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service_session',
        client_secret: @external_service2.puavoServiceSecret,
        redirect_uri: 'http://session_test.example.com',
        code: code
      }

      assert_equal last_response.status, 200
      assert_equal last_response.header['Content-Type'], 'application/json'

      # Validate the bearer token
      token = JSON.parse(last_response.body)
      validate_access_token(token)

      # Validate the access token
      access_token = decode_token(token['access_token'], audience: 'puavo-rest-userinfo')

      assert_equal access_token['iss'], 'https://api.opinsys.fi'
      assert_equal access_token['sub'], @user.uuid
      assert_equal access_token['aud'], 'puavo-rest-userinfo'
      assert_equal access_token['scopes'], 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups'
      assert_equal access_token['allowed_endpoints'], ['/oidc/userinfo']
      assert_equal access_token['organisation_domain'], 'example.puavo.net'
      assert_equal access_token['user_dn'], @user.dn.to_s

      # Validate the ID token
      id_token = decode_token(token['id_token'], audience: 'test_login_service_session')

      assert_equal id_token['iss'], 'https://api.opinsys.fi'
      assert_equal id_token['sub'], @user.uuid
      assert_equal id_token['aud'], 'test_login_service_session'
      assert_equal id_token['nonce'], 'quux'
      assert_equal id_token['given_name'], @user.first_name
      assert_equal id_token['family_name'], @user.last_name
      assert_equal id_token['name'], "#{@user.first_name} #{@user.last_name}"
      assert_equal id_token['preferred_username'], @user.username
      assert_equal id_token['puavo.uuid'], @user.uuid
      assert_equal id_token['puavo.puavoid'], @user.id
      assert_equal id_token['puavo.roles'], ['student']
      assert_equal id_token['puavo.authenticated_using'], 'username+password'

      assert_equal id_token['puavo.schools'].count, 1
      assert_equal id_token['puavo.schools'][0]['name'], 'Gryffindor'
      assert_equal id_token['puavo.schools'][0]['abbreviation'], 'gryffindor'
      assert_equal id_token['puavo.schools'][0]['puavoid'], @school.id.to_i
      assert_equal id_token['puavo.schools'][0]['primary'], true

      assert_equal id_token['puavo.groups'].count, 1
      assert_equal id_token['puavo.groups'][0]['name'], 'Group 1'
      assert_equal id_token['puavo.groups'][0]['abbreviation'], 'group1'
      assert_equal id_token['puavo.groups'][0]['puavoid'], @group.id.to_i
      assert_equal id_token['puavo.groups'][0]['type'], 'teaching group'
      assert_equal id_token['puavo.groups'][0]['school_abbreviation'], 'gryffindor'

      # Part 2: Do everything again, but pass the session key with the request and there should be no login form
      set_cookie "#{PUAVO_SSO_SESSION_KEY}=#{session_key}"

      get format_uri('/oidc/authorize',
                     client_id: 'test_login_service_session',
                     redirect_uri: 'http://session_test.example.com',
                     response_type: 'code',
                     scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                     extra: { 'state' => 'blurf', 'nonce' => 'mangle' })

      # There must be no session cookie in this response, since we already have a session
      assert last_response.redirect?
      assert_equal last_response.status, 302
      assert_equal last_response.headers.include?('Location'), true
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false

      # Load the new values
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values['state'], 'blurf'
      assert_equal redirect.query_values.include?('nonce'), false
      assert_equal redirect.query_values.include?('scope'), false   # the scopes have not changed
      code = redirect.query_values['code']

      # We can now go directly to the token part
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service_session',
        client_secret: @external_service2.puavoServiceSecret,
        redirect_uri: 'http://session_test.example.com',
        code: code
      }

      assert_equal last_response.status, 200
      assert_equal last_response.header['Content-Type'], 'application/json'

      # Validate the bearer token again
      token2 = JSON.parse(last_response.body)
      validate_access_token(token2)

      # Validate both tokens again
      access_token2 = decode_token(token2['access_token'], audience: 'puavo-rest-userinfo')
      assert_equal access_token2['iss'], 'https://api.opinsys.fi'
      assert_equal access_token2['sub'], @user.uuid
      assert_equal access_token2['aud'], 'puavo-rest-userinfo'
      assert_equal access_token2['scopes'], 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups'
      assert_equal access_token2['allowed_endpoints'], ['/oidc/userinfo']
      assert_equal access_token2['organisation_domain'], 'example.puavo.net'
      assert_equal access_token2['user_dn'], @user.dn.to_s

      id_token2 = decode_token(token2['id_token'], audience: 'test_login_service_session')
      assert_equal id_token2['iss'], 'https://api.opinsys.fi'
      assert_equal id_token2['sub'], @user.uuid
      assert_equal id_token2['aud'], 'test_login_service_session'
      assert_equal id_token2['nonce'], 'mangle'
      assert_equal id_token2['given_name'], @user.first_name
      assert_equal id_token2['family_name'], @user.last_name
      assert_equal id_token2['name'], "#{@user.first_name} #{@user.last_name}"
      assert_equal id_token2['preferred_username'], @user.username
      assert_equal id_token2['puavo.uuid'], @user.uuid
      assert_equal id_token2['puavo.puavoid'], @user.id
      assert_equal id_token2['puavo.roles'], ['student']
      assert_equal id_token2['puavo.authenticated_using'], 'username+password'

      assert_equal id_token2['puavo.schools'].count, 1
      assert_equal id_token2['puavo.schools'][0]['name'], 'Gryffindor'
      assert_equal id_token2['puavo.schools'][0]['abbreviation'], 'gryffindor'
      assert_equal id_token2['puavo.schools'][0]['puavoid'], @school.id.to_i
      assert_equal id_token2['puavo.schools'][0]['primary'], true

      assert_equal id_token2['puavo.groups'].count, 1
      assert_equal id_token2['puavo.groups'][0]['name'], 'Group 1'
      assert_equal id_token2['puavo.groups'][0]['abbreviation'], 'group1'
      assert_equal id_token2['puavo.groups'][0]['puavoid'], @group.id.to_i
      assert_equal id_token2['puavo.groups'][0]['type'], 'teaching group'
      assert_equal id_token2['puavo.groups'][0]['school_abbreviation'], 'gryffindor'
    end

    it 'a service that does not have sessions enabled must not return a session cookie' do
      clear_cookies

      get format_uri('/oidc/authorize',
                     client_id: 'test_login_service',
                     redirect_uri: 'http://normal_service.example.com',
                     response_type: 'code',
                     scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups')

      # Ensure we're in the login form
      assert_equal last_response.status, 401
      assert last_response.body.include?('Login to service <span>Normal service</span>')
      assert get_named_form_value('type') == 'oidc'

      # A session cookie must not be present
      assert_equal last_response.headers.include?('Location'), false
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false
    end

    it 'fake session key will fail' do
      clear_cookies
      set_cookie "#{PUAVO_SSO_SESSION_KEY}=foobar"

      get format_uri('/oidc/authorize',
                     client_id: 'test_login_service_session',
                     redirect_uri: 'http://session_test.example.com',
                     response_type: 'code',
                     scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                     extra: { 'state' => 'blurf', 'nonce' => 'mangle' })

      # Ensure we're in the login form
      assert_equal last_response.status, 401
      assert last_response.body.include?('Login to service <span>Service with SSO sessions</span>')
      assert get_named_form_value('type') == 'oidc'
    end

    it 'session expiration' do
      # Part 1: Create a session
      clear_cookies
      get format_uri('/oidc/authorize',
                     client_id: 'test_login_service_session',
                     redirect_uri: 'http://session_test.example.com',
                     response_type: 'code',
                     scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                     extra: { 'state' => 'foo' })

      assert_equal last_response.status, 401
      assert last_response.body.include?('Login to service <span>Service with SSO sessions</span>')
      assert get_named_form_value('type') == 'oidc'

      post '/oidc/authorize/post', {
        type: 'oidc',
        request_id: get_named_form_value('request_id'),
        state_key: get_named_form_value('state_key'),
        return_to: get_named_form_value('return_to'),
        username: 'bob.brown@example.puavo.net',
        password: 'secret',
      }

      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values['state'], 'foo'
      assert_equal redirect.query_values.include?('nonce'), false
      assert_equal redirect.query_values.include?('scope'), false   # the scopes have not changed
      code = redirect.query_values['code']

      assert_equal last_response.headers.include?('Location'), true
      assert_equal last_response.headers.include?('Set-Cookie'), true
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), true
      session_key = last_response.cookies[PUAVO_SSO_SESSION_KEY][0]

      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service_session',
        client_secret: @external_service2.puavoServiceSecret,
        redirect_uri: 'http://session_test.example.com',
        code: code
      }

      assert_equal last_response.status, 200
      assert_equal last_response.header['Content-Type'], 'application/json'

      token = JSON.parse(last_response.body)
      validate_access_token(token)

      id_token = decode_token(token['id_token'], audience: 'test_login_service_session')
      assert_equal id_token['iss'], 'https://api.opinsys.fi'
      assert_equal id_token['aud'], 'test_login_service_session'
      assert_equal id_token.include?('nonce'), false
      assert_equal id_token['puavo.puavoid'], @user.id
      puavoid = id_token['puavo.puavoid']

      # Part 2: Expire the session. Manually delete the Redis session entries. We could use Timecop
      # to fool Ruby code into thinking the session is expired, but we can't trick Redis.
      REDIS_CONNECTION.del("sso_session:user:#{puavoid}")
      REDIS_CONNECTION.del("sso_session:data:#{session_key}")

      # Part 3: Try to use the session cookie, it must fail
      set_cookie "#{PUAVO_SSO_SESSION_KEY}=#{session_key}"

      get format_uri('/oidc/authorize',
                     client_id: 'test_login_service_session',
                     redirect_uri: 'http://session_test.example.com',
                     response_type: 'code',
                     scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups')

      assert_equal last_response.status, 401
      assert last_response.body.include?('Login to service <span>Service with SSO sessions</span>')
      assert get_named_form_value('type') == 'oidc'
    end
  end

  describe 'OpenID Connect + MFA tests' do
    before(:each) do
      PuavoRest::Organisation.refresh

      @external_service = ExternalService.new
      @external_service.classes = ['top', 'puavoJWTService']
      @external_service.cn = 'The Service'
      @external_service.puavoServiceDomain = 'service.example.com'
      @external_service.puavoServiceSecret = 'secret'
      @external_service.puavoServiceTrusted = false
      @external_service.save!

      @external_service2 = ExternalService.new
      @external_service2.classes = ['top', 'puavoJWTService']
      @external_service2.cn = 'Service with SSO sessions'
      @external_service2.puavoServiceDomain = 'session_test.example.com'
      @external_service2.puavoServiceSecret = 'password'
      @external_service2.puavoServiceTrusted = false
      @external_service2.save!

      activate_organisation_services([@external_service.dn.to_s, @external_service2.dn.to_s])

      setup_login_clients([
        {
          client_id: 'test_login_service',
          enabled: true,
          puavo_service_dn: @external_service.dn.to_s,
          redirects: ['http://service.example.com'],
          scopes: %w[openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups]
        },
        {
          client_id: 'test_login_service_session',
          enabled: true,
          puavo_service_dn: @external_service2.dn.to_s,
          redirects: ['http://session_test.example.com'],
          scopes: %w[openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups]
        }
      ])

      # Create a user who uses MFA
      @mfa_user = PuavoRest::User.new(
        first_name: 'Bob',
        last_name: 'Page',
        username: 'bob.page',
        password: '9Kpj03Tdf2HVTWpNPr1NE7eOY5SABcfhAWswWRfdTIDFlovk5f',
        roles: ['admin'],
        school_dns: [@school.dn.to_s],
        mfa_enabled: true,
      )

      @mfa_user.save!

      # Stub MFA server requests
      mfa_server_url = 'http://127.0.0.1:9999/v1/authenticate'
      mfa_bearer = "Bearer #{CONFIG['mfa_server']['bearer_key']}"

      mfa_success = {
        'status' => 'success',
        'messages' => {
          '1002' => 'Code accepted.'
        }
      }.to_json

      mfa_fail = {
        'status' => 'fail',
        'messages' => {
          '2002' => 'Invalid code.'
        }
      }.to_json

      # Stub the MFA server requests. The server's not installed in puavo-standalone,
      # and installing and configuring it would be a nightmare to automate. And actually
      # setting up the MFA data would be almost impossible. So we'll fake the requests.
      # Both success and failure responses (including HTTP status codes) were adapted
      # from the real responses the MFA server returns.

      # This request must succeed
      stub_request(:post, mfa_server_url)
        .with(
          headers: { 'Authorization' => mfa_bearer },
          body: {
            'userid' => @mfa_user.uuid,
            'code' => '000451'
          }
        )
        .to_return(
          status: 200,
          headers: { 'X-Request-ID' => '-FAKEFAKE-' },
          body: mfa_success
        )

      # All these requests must fail
      ['123456', '234567', '345678', '456789', '111111'].each do |code|
        stub_request(:post, mfa_server_url)
          .with(
            headers: { 'Authorization' => mfa_bearer },
            body: {
              'userid' => @mfa_user.uuid,
              'code' => code
            }
          )
          .to_return(
            status: 403,
            headers: { 'X-Request-ID' => '-FAKEFAKE-' },
            body: mfa_fail
          )
      end

    end

    def go_to_mfa_form
      # Extract the MFA form URL from the response headers, and fetch the form.
      # Can't just directly go to /v3/mfa, because we need the session token.
      mfa_form_path = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal mfa_form_path.path, '/v3/mfa'

      mfa_form_path.scheme = nil
      mfa_form_path.host = nil

      get mfa_form_path.to_s

      # The caller needs this
      mfa_form_path
    end

    # Performs all the pre-MFA form steps
    def authenticate_user
      get format_uri('/oidc/authorize',
                     client_id: 'test_login_service',
                     redirect_uri: 'http://service.example.com',
                     response_type: 'code',
                     scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                     extra: { 'state' => 'foo', 'nonce' => 'bar' })

      assert_equal last_response.status, 401
      assert last_response.body.include?('Login to service <span>The Service</span>')
      assert get_named_form_value('type') == 'oidc'
      assert_equal css('input[name="organisation"]').count, 0
      assert_equal css("div.col-orgname").count, 0

      post '/oidc/authorize/post', {
        type: 'oidc',
        request_id: get_named_form_value('request_id'),
        state_key: get_named_form_value('state_key'),
        return_to: get_named_form_value('return_to'),
        username: 'bob.page@example.puavo.net',
        password: '9Kpj03Tdf2HVTWpNPr1NE7eOY5SABcfhAWswWRfdTIDFlovk5f',
      }

      # Step 2: The MFA form
      assert last_response.redirect?
      assert last_response.body.empty?

      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.path, '/v3/mfa'

      # These must not be present yet
      assert_equal redirect.query_values.include?('iss'), false
      assert_equal redirect.query_values.include?('state'), false
      assert_equal redirect.query_values.include?('nonce'), false
      assert_equal redirect.query_values.include?('scope'), false
      assert_equal redirect.query_values.include?('token'), true
    end

    # Like above, but uses a service that has SSO sessions enabled
    def authenticate_user_session
      get format_uri('/oidc/authorize',
                     client_id: 'test_login_service_session',
                     redirect_uri: 'http://session_test.example.com',
                     response_type: 'code',
                     scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                     extra: { 'state' => 'foo', 'nonce' => 'bar' })

      assert_equal last_response.status, 401
      assert last_response.body.include?('Login to service <span>Service with SSO sessions</span>')
      assert get_named_form_value('type') == 'oidc'
      assert_equal css('input[name="organisation"]').count, 0
      assert_equal css("div.col-orgname").count, 0

      post '/oidc/authorize/post', {
        type: 'oidc',
        request_id: get_named_form_value('request_id'),
        state_key: get_named_form_value('state_key'),
        return_to: get_named_form_value('return_to'),
        username: 'bob.page@example.puavo.net',
        password: '9Kpj03Tdf2HVTWpNPr1NE7eOY5SABcfhAWswWRfdTIDFlovk5f',
      }

      # Step 2: The MFA form
      assert last_response.redirect?
      assert last_response.body.empty?

      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.path, '/v3/mfa'

      # These must not be present yet
      assert last_response.body.empty?
      assert_equal redirect.query_values.include?('iss'), false
      assert_equal redirect.query_values.include?('state'), false
      assert_equal redirect.query_values.include?('nonce'), false
      assert_equal redirect.query_values.include?('scope'), false
      assert_equal redirect.query_values.include?('token'), true
    end

    it 'Basic OpenID Connect login with MFA' do
      # Step 1: Log in
      get format_uri('/oidc/authorize',
                     client_id: 'test_login_service',
                     redirect_uri: 'http://service.example.com',
                     response_type: 'code',
                     scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                     extra: { 'state' => 'foo', 'nonce' => 'bar' })

      assert_equal last_response.status, 401
      assert last_response.body.include?('Login to service <span>The Service</span>')
      assert get_named_form_value('type') == 'oidc'
      assert_equal css('input[name="organisation"]').count, 0
      assert_equal css("div.col-orgname").count, 0

      post '/oidc/authorize/post', {
        type: 'oidc',
        request_id: get_named_form_value('request_id'),
        state_key: get_named_form_value('state_key'),
        return_to: get_named_form_value('return_to'),
        username: 'bob.page@example.puavo.net',
        password: '9Kpj03Tdf2HVTWpNPr1NE7eOY5SABcfhAWswWRfdTIDFlovk5f',
      }

      # Step 2: The MFA form
      assert last_response.redirect?
      assert last_response.body.empty?

      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.path, '/v3/mfa'

      # These must not be present yet
      assert_equal redirect.query_values.include?('iss'), false
      assert_equal redirect.query_values.include?('state'), false
      assert_equal redirect.query_values.include?('nonce'), false
      assert_equal redirect.query_values.include?('scope'), false
      assert_equal redirect.query_values.include?('token'), true

      mfa_form_path = go_to_mfa_form()

      assert_equal last_response.status, 401    # still 401 even though Kerberos is complete by now
      assert last_response.body.include?('Two-factor authentication has been activated on your account.')

      # Ensure the form's hidden token is the same as in the URL (it's not necessary to validate
      # this, but let's make sure)
      assert_equal css('input[name="token"]').first.attributes['value'].value, mfa_form_path.query_values['token']

      # Now we're in the MFA form. "Fill" and post it.
      post '/v3/mfa', {
        'token' => mfa_form_path.query_values['token'],
        'mfa_code' => '000451',
      }

      # We've stubbed this code, so it must succeed
      assert_equal last_response.status, 302
      assert_equal last_response.headers.include?('Location'), true
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.path, '/oidc/authorize/mfa_complete'
      assert redirect.query_values.include?('state_key')

      # Follow the MFA form completion redirect
      redirect.scheme = nil
      redirect.host = nil
      get redirect

      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])

      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values['state'], 'foo'
      assert_equal redirect.query_values.include?('nonce'), false
      assert_equal redirect.query_values.include?('scope'), false   # the scopes have not changed
      code = redirect.query_values['code']

      # No sessions here
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false

      # Step 2: Acquire the access and ID tokens
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service',
        client_secret: @external_service.puavoServiceSecret,
        redirect_uri: 'http://service.example.com',
        code: code
      }

      assert_equal last_response.status, 200
      assert_equal last_response.header['Content-Type'], 'application/json'

      # Check the bearer token
      token = JSON.parse(last_response.body)
      validate_access_token(token)

      # Validate the access token
      access_token = decode_token(token['access_token'], audience: 'puavo-rest-userinfo')

      assert_equal access_token['iss'], 'https://api.opinsys.fi'
      assert_equal access_token['sub'], @mfa_user.uuid
      assert_equal access_token['aud'], 'puavo-rest-userinfo'
      assert_equal access_token['scopes'], 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups'
      assert_equal access_token['allowed_endpoints'], ['/oidc/userinfo']
      assert_equal access_token['organisation_domain'], 'example.puavo.net'
      assert_equal access_token['user_dn'], @mfa_user.dn.to_s

      # Validate the ID token
      id_token = decode_token(token['id_token'], audience: 'test_login_service')

      assert_equal id_token['iss'], 'https://api.opinsys.fi'
      assert_equal id_token['sub'], @mfa_user.uuid
      assert_equal id_token['aud'], 'test_login_service'
      assert_equal id_token['nonce'], 'bar'
      assert_equal id_token['given_name'], @mfa_user.first_name
      assert_equal id_token['family_name'], @mfa_user.last_name
      assert_equal id_token['name'], "#{@mfa_user.first_name} #{@mfa_user.last_name}"
      assert_equal id_token['preferred_username'], @mfa_user.username
      assert_equal id_token['puavo.uuid'], @mfa_user.uuid
      assert_equal id_token['puavo.puavoid'], @mfa_user.id
      assert_equal id_token['puavo.roles'], ['admin']
      assert_equal id_token['puavo.authenticated_using'], 'username+password'

      assert_equal id_token['puavo.schools'].count, 1
      assert_equal id_token['puavo.schools'][0]['name'], 'Gryffindor'
      assert_equal id_token['puavo.schools'][0]['abbreviation'], 'gryffindor'
      assert_equal id_token['puavo.schools'][0]['puavoid'], @school.id.to_i
      assert_equal id_token['puavo.schools'][0]['primary'], true

      assert_equal id_token['puavo.groups'].count, 0
    end

    it 'basic failed MFA login' do
      authenticate_user()
      mfa_form_path = go_to_mfa_form()

      assert_equal last_response.status, 401    # still 401 even though Kerberos is complete by now
      assert last_response.body.include?('Two-factor authentication has been activated on your account.')
      assert_equal css('input[name="token"]').first.attributes['value'].value, mfa_form_path.query_values['token']

      # Enter one of the invalid codes
      post '/v3/mfa', {
        'token' => mfa_form_path.query_values['token'],
        'mfa_code' => '123456',
      }

      # Ensure the check failed
      assert_equal last_response.status, 401
      assert_equal last_response.headers.include?('Location'), false
      assert last_response.body.include?('Two-factor authentication has been activated on your account.')
      assert last_response.body.include?('<div id="mfa_invalid_code">Incorrect code</div>')
    end

    it 'multiple failed attempts' do
      authenticate_user()
      mfa_form_path = go_to_mfa_form()

      # Post the form four times with incorrect codes
      ['123456', '234567', '345678', '456789'].each do |code|
        post '/v3/mfa', {
          'token' => mfa_form_path.query_values['token'],
          'mfa_code' => code,
        }

        # Ensure each check fails
        assert_equal last_response.status, 401
        assert_equal last_response.headers.include?('Location'), false
        assert_equal css('input[name="token"]').empty?, false
        assert_equal css('input#mfa_code').empty?, false
        assert last_response.body.include?('Two-factor authentication has been activated on your account.')
        assert last_response.body.include?('<div id="mfa_invalid_code">Incorrect code</div>')
      end

      # Then the final (fifth) check. This must halt the whole process.
      post '/v3/mfa', {
        'token' => mfa_form_path.query_values['token'],
        'mfa_code' => '111111',
      }

      assert_equal last_response.status, 401
      assert_equal last_response.headers.include?('Location'), false
      assert_equal css('input[name="token"]').empty?, true
      assert_equal css('input#mfa_code').empty?, true
      assert_equal last_response.body.include?('Two-factor authentication has been activated on your account.'), false
      assert last_response.body.include?('Too many failed two-factor login attempts. Login halted. Go to the original login form and try logging in again.')
    end

    it 'expired MFA session must fail' do
      authenticate_user()
      mfa_form_path = go_to_mfa_form()

      # Delete the Redis session entries, making the attempt fail even if the code is correct.
      # This simulates the user waiting for too long.
      REDIS_CONNECTION.del("mfa_sso_login:#{@mfa_user.uuid}")
      REDIS_CONNECTION.del("mfa_sso_login:#{mfa_form_path.query_values['token']}")

      post '/v3/mfa', {
        'token' => mfa_form_path.query_values['token'],
        'mfa_code' => '987654',
      }

      # Ensure the check failed
      assert_equal last_response.status, 401
      assert_equal last_response.headers.include?('Location'), false
      assert_equal last_response.body.include?('Two-factor authentication has been activated on your account.'), false
      assert last_response.body.include?('Your login attempt has expired. Go to the original login form and try logging in again.')
    end

    it 'invalid MFA session token' do
      get '/v3/mfa?token=foobar'

      assert_equal last_response.status, 401
      assert_equal last_response.headers.include?('Location'), false
      assert_equal last_response.body.include?('Two-factor authentication has been activated on your account.'), false
      assert last_response.body.include?('Your login attempt has expired. Go to the original login form and try logging in again.')
    end

    it 'SSO sessions with MFA work' do
      # Authenticate the user into a service that uses sessions
      clear_cookies
      authenticate_user_session()

      mfa_form_path = go_to_mfa_form()
      assert_equal last_response.status, 401
      assert last_response.body.include?('Two-factor authentication has been activated on your account.')
      assert_equal css('input[name="token"]').first.attributes['value'].value, mfa_form_path.query_values['token']

      # Post the MFA form
      post '/v3/mfa', {
        'token' => mfa_form_path.query_values['token'],
        'mfa_code' => '000451',
      }

      assert last_response.redirect?
      assert last_response.body.empty?
      assert_equal last_response.headers.include?('Location'), true
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.path, '/oidc/authorize/mfa_complete'
      assert redirect.query_values.include?('state_key')

      # Follow the MFA form completion redirect
      redirect.scheme = nil
      redirect.host = nil
      get redirect

      assert last_response.redirect?
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal last_response.headers.include?('Set-Cookie'), true
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), true
      session_key = last_response.cookies[PUAVO_SSO_SESSION_KEY][0]
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values['state'], 'foo'
      assert_equal redirect.query_values.include?('nonce'), false
      assert_equal redirect.query_values.include?('scope'), false   # the scopes have not changed
      code = redirect.query_values['code']

      # We've passed the MFA form and we have a session key. Acquire the tokens.
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service_session',
        client_secret: @external_service2.puavoServiceSecret,
        redirect_uri: 'http://session_test.example.com',
        code: code
      }

      assert_equal last_response.status, 200
      assert_equal last_response.header['Content-Type'], 'application/json'

      # Check the bearer token
      token = JSON.parse(last_response.body)
      validate_access_token(token)

      # Validate the access token
      access_token = decode_token(token['access_token'], audience: 'puavo-rest-userinfo')

      assert_equal access_token['iss'], 'https://api.opinsys.fi'
      assert_equal access_token['sub'], @mfa_user.uuid
      assert_equal access_token['aud'], 'puavo-rest-userinfo'
      assert_equal access_token['scopes'], 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups'
      assert_equal access_token['allowed_endpoints'], ['/oidc/userinfo']
      assert_equal access_token['organisation_domain'], 'example.puavo.net'
      assert_equal access_token['user_dn'], @mfa_user.dn.to_s

      # Validate the ID token
      id_token = decode_token(token['id_token'], audience: 'test_login_service_session')

      assert_equal id_token['iss'], 'https://api.opinsys.fi'
      assert_equal id_token['sub'], @mfa_user.uuid
      assert_equal id_token['aud'], 'test_login_service_session'
      assert_equal id_token['nonce'], 'bar'
      assert_equal id_token['given_name'], @mfa_user.first_name
      assert_equal id_token['family_name'], @mfa_user.last_name
      assert_equal id_token['name'], "#{@mfa_user.first_name} #{@mfa_user.last_name}"
      assert_equal id_token['preferred_username'], @mfa_user.username
      assert_equal id_token['puavo.uuid'], @mfa_user.uuid
      assert_equal id_token['puavo.puavoid'], @mfa_user.id
      assert_equal id_token['puavo.roles'], ['admin']
      assert_equal id_token['puavo.authenticated_using'], 'username+password'

      assert_equal id_token['puavo.schools'].count, 1
      assert_equal id_token['puavo.schools'][0]['name'], 'Gryffindor'
      assert_equal id_token['puavo.schools'][0]['abbreviation'], 'gryffindor'
      assert_equal id_token['puavo.schools'][0]['puavoid'], @school.id.to_i
      assert_equal id_token['puavo.schools'][0]['primary'], true

      assert_equal id_token['puavo.groups'].count, 0

      # The session has been established, so try to use it. There should be no login/MFA forms.
      clear_cookies
      set_cookie "#{PUAVO_SSO_SESSION_KEY}=#{session_key}"

      get format_uri('/oidc/authorize',
                     client_id: 'test_login_service_session',
                     redirect_uri: 'http://session_test.example.com',
                     response_type: 'code',
                     scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                     extra: { 'state' => 'blurf', 'nonce' => 'mangle' })

      # There must be no session cookie in this response, since we already have a session
      assert last_response.redirect?
      assert_equal last_response.status, 302
      assert_equal last_response.headers.include?('Location'), true
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false

      # Load the new values
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values['iss'], 'https://api.opinsys.fi'
      assert_equal redirect.query_values['state'], 'blurf'
      assert_equal redirect.query_values.include?('nonce'), false
      assert_equal redirect.query_values.include?('scope'), false   # the scopes have not changed
      code = redirect.query_values['code']

      # We can now go directly to the token part
      post '/oidc/token', {
        grant_type: 'authorization_code',
        client_id: 'test_login_service_session',
        client_secret: @external_service2.puavoServiceSecret,
        redirect_uri: 'http://session_test.example.com',
        code: code
      }

      assert_equal last_response.status, 200
      assert_equal last_response.header['Content-Type'], 'application/json'

      # Validate the bearer token again
      token2 = JSON.parse(last_response.body)
      validate_access_token(token2)

      # Try to login again without the cookie, we must get the login screen
      clear_cookies

      get format_uri('/oidc/authorize',
                     client_id: 'test_login_service_session',
                     redirect_uri: 'http://session_test.example.com',
                     response_type: 'code',
                     scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                     extra: { 'state' => 'blurf', 'nonce' => 'mangle' })

      assert_equal last_response.status, 401
      assert last_response.body.include?('Login to service <span>Service with SSO sessions</span>')
      assert get_named_form_value('type') == 'oidc'

      # Try to login to another service with the session, it should fail
      clear_cookies
      set_cookie "#{PUAVO_SSO_SESSION_KEY}=#{session_key}"

      get format_uri('/oidc/authorize',
                     client_id: 'test_login_service',
                     redirect_uri: 'http://service.example.com',
                     response_type: 'code',
                     scope: 'openid profile puavo.read.userinfo.schools puavo.read.userinfo.groups',
                     extra: { 'state' => 'foo', 'nonce' => 'bar' })

      assert_equal last_response.status, 401
      assert last_response.body.include?('Login to service <span>The Service</span>')
    end

    it 'a failed MFA check must not create an SSO session' do
      # Authenticate
      clear_cookies
      authenticate_user_session()

      mfa_form_path = go_to_mfa_form()
      assert_equal last_response.status, 401

      # Post the form four times with incorrect codes
      ['123456', '234567', '345678', '456789'].each do |code|
        post '/v3/mfa', {
          'token' => mfa_form_path.query_values['token'],
          'mfa_code' => code,
        }

        # Ensure each check fails
        assert_equal last_response.status, 401
        assert_equal last_response.headers.include?('Location'), false
        assert_equal last_response.headers.include?('Set-Cookie'), false
        assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false
        assert last_response.body.include?('<div id="mfa_invalid_code">Incorrect code</div>')
      end

      # Then the final check. This must halt the whole process.
      post '/v3/mfa', {
        'token' => mfa_form_path.query_values['token'],
        'mfa_code' => '111111',
      }

      assert_equal last_response.headers.include?('Location'), false
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false
      assert last_response.body.include?('Too many failed two-factor login attempts. Login halted. Go to the original login form and try logging in again.')
    end
  end
end

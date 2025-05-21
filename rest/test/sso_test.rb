
require_relative "./helper"

require "addressable/uri"
require "jwt"

describe PuavoRest::SSO do
  def activate_organisation_services(s)
    PuavoRest::Organisation.all.each do |org|
      unless ['puavo.net', 'hogwarts.puavo.net', ''].include?(org.domain)
        org.external_services = s
        org.save!
      end
    end

    PuavoRest::Organisation.refresh
  end

  before(:each) do
    Puavo::Test.clean_up_ldap
    setup_ldap_admin_connection()

    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor"
    )

    @group = PuavoRest::Group.new(
      :abbreviation => 'group1',
      :name         => 'Group 1',
      :school_dn    => @school.dn.to_s,
      :type         => 'teaching group')
    @group.save!

    @user = PuavoRest::User.new(
      :email          => 'bob@example.com',
      :first_name     => 'Bob',
      :last_name      => 'Brown',
      :password       => 'secret',
      :roles          => [ 'student' ],
      :school_dns     => [ @school.dn.to_s ],
      :username       => 'bob',
    )
    @user.save!
    @user.teaching_group = @group   # XXX weird that this must be here

    @user2 = PuavoRest::User.new(
      :first_name     => 'Verified',
      :last_name      => 'User',
      :username       => 'verified',
      :roles          => [ 'teacher' ],
      :school_dns     => [ @school.dn.to_s ],
      :password       => 'trustno1',
      :email          => ['verified@example.com'],
      :verified_email => ['verified@example.com'],
      :primary_email  => 'verified@example.com',
    )

    @user2.save!

    original_verbosity = $VERBOSE
    $VERBOSE = nil
    @orig_config = CONFIG.dup
    CONFIG.delete("default_organisation_domain")
    CONFIG["bootserver"] = false
    $VERBOSE = original_verbosity

    PuavoRest::Organisation.refresh

    @external_service = ExternalService.new
    @external_service.classes = ["top", "puavoJWTService"]
    @external_service.cn = "Testing Service"
    @external_service.puavoServiceDomain = "test-client-service.example.com"
    @external_service.puavoServiceSecret = "this is a shared secret"
    @external_service.description = "Description"
    @external_service.mail = "contact@test-client-service.example.com"
    @external_service.puavoServiceTrusted = false
    @external_service.save!

    @external_service2 = ExternalService.new
    @external_service2.classes = ['top', 'puavoJWTService']
    @external_service2.cn = 'Service with SSO sessions'
    @external_service2.puavoServiceDomain = 'session_test.example.com'
    @external_service2.puavoServiceSecret = 'password'
    @external_service2.puavoServiceTrusted = false
    @external_service2.save!

    @external_service3 = ExternalService.new
    @external_service3.classes = ['top', 'puavoJWTService']
    @external_service3.cn = 'Another service with SSO sessions'
    @external_service3.puavoServiceDomain = 'session_test2.example.com'
    @external_service3.puavoServiceSecret = 'password2'
    @external_service3.puavoServiceTrusted = false
    @external_service3.save!

    activate_organisation_services([@external_service.dn.to_s, @external_service2.dn.to_s, @external_service3.dn.to_s])
  end

  after do
    original_verbosity = $VERBOSE
    $VERBOSE = nil
    CONFIG = @orig_config
    $VERBOSE = original_verbosity
  end


  it "responds with 400 error for missing return_to" do
    get "/v3/sso"
    assert_equal 400, last_response.status
  end

  it "responds 401 for unknown services" do
    url = Addressable::URI.parse("/v3/sso")
    url.query_values = { "return_to" => "http://unknown.example.com/path" }
    get url.to_s
    assert_equal 401, last_response.status
  end

  it "responds 401 for bad credentials" do
    url = Addressable::URI.parse("/v3/sso")
    url.query_values = { "return_to" => "http://test-client-service.example.com/path" }
    basic_authorize "bob", "bad"
    get url.to_s
    assert_equal 401, last_response.status
  end

  it "adds 'WWW-Authenticate: Negotiate' for requests without credentials" do
    url = Addressable::URI.parse("/v3/sso")
    url.query_values = { "return_to" => "http://test-client-service.example.com/path?foo=bar" }

    get url.to_s, {}, {
      # Only firefox on linux will get the negotiate request
      "HTTP_USER_AGENT" => "Mozilla/5.0 (X11; Ubuntu; Linux i686; rv:31.0) Gecko/20100101 Firefox/31.0"
    }

    # This is required for the Kerberos-GSSAPI based authentication for Firefox.
    # Without this header firefox will never send the kerberos ticket.
    assert_equal(
      "Negotiate",
      last_response.headers["WWW-Authenticate"],
      "WWW-Authenticate: Negotiate must be present on the login page request"
    )

    assert_equal 401, last_response.status
  end

  it "'WWW-Authenticate: Negotiate' is not added for others" do
    url = Addressable::URI.parse("/v3/sso")
    url.query_values = { "return_to" => "http://test-client-service.example.com/path?foo=bar" }

    get url.to_s

    assert(!last_response.headers["WWW-Authenticate"])
    assert_equal 401, last_response.status
  end

  describe "roles in jwt" do

    it "is set to 'schooladmin' when user is a school admin" do
      @user.roles = [ 'admin' ]
      @user.save!

      # to use .add_admin() must use the puavo-web object
      _user = User.find(:first, :attribute => 'puavoId', :value => @user.id)
      @school.add_admin(_user)

      url = Addressable::URI.parse("/v3/sso")
      url.query_values = { "return_to" => "http://test-client-service.example.com/path?foo=bar" }
      basic_authorize "bob", "secret"
      get url.to_s
      assert last_response.headers["Location"]
      redirect_url = Addressable::URI.parse(last_response.headers["Location"])
      jwt_decode_data = JWT.decode(
        redirect_url.query_values["jwt"],
        @external_service.puavoServiceSecret
      )
      jwt = jwt_decode_data[0] # jwt_decode_data is [payload, header]

      assert_equal ["admin", "schooladmin"], jwt["schools"][0]["roles"]
    end
  end

  it 'HTML in the domain is properly escaped' do
    url = Addressable::URI.parse('/v3/sso')

    url.query_values = {
      'return_to' => 'http://test-client-service.example.com',
      'organisation' => '<script>alert("hax!");</script>'
    }

    get url.to_s, {}, {
      'HTTP_HOST' => 'api.puavo.net'
    }

    assert_equal last_response.body.include?('<script>alert("hax!");</script>'), false

    # When the organisation is set, it appears twice in the HTML (once in a hidden input field,
    # and once in a visible text)
    assert_equal last_response.body.scan('&lt;script&gt;alert(&quot;hax!&quot;);&lt;&#x2F;script&gt;').count, 2

    # Nokogiri "helpfully" unescapes the value for us
    assert_equal css('form input[name="organisation"]').first.attributes['value'].value, '<script>alert("hax!");</script>'
    assert_equal css('form div.row div.col-orgname span').text, '@<script>alert("hax!");</script>'
  end

  describe 'SSO session tests' do
    it 'a basic SSO session test' do
      clear_cookies

      # Step 1: Acquire a session key. The service session_test.example.com has been configured
      # in organisations.yml to have SSO sessions enabled.
      post '/v3/sso', {
        'username' => 'bob',
        'password' => 'secret',
        'organisation' => 'example.puavo.net',
        'return_to' => 'https://session_test.example.com'
      }

      assert_equal last_response.status, 302
      assert_equal last_response.headers.include?('Location'), true
      assert_equal last_response.headers.include?('Set-Cookie'), true
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), true
      session_key = last_response.cookies[PUAVO_SSO_SESSION_KEY][0]

      # Extract and verify the JWT
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      jwt = JWT.decode(redirect.query_values['jwt'], @external_service2.puavoServiceSecret)[0]

      assert_equal 'bob', jwt['username']
      assert_equal 'Bob', jwt['first_name']
      assert_equal 'Brown', jwt['last_name']
      assert_equal 'student', jwt['user_type']
      assert_equal 'bob@example.com', jwt['email']
      assert_equal 'Example Organisation', jwt['organisation_name']
      assert_equal 'example.puavo.net', jwt['organisation_domain']
      assert_equal '/', jwt['external_service_path_prefix']
      assert_equal @school.puavoId.to_s, jwt['primary_school_id']

      # We'll need this later
      puavoid = jwt['puavo_id']

      # Step 2: Use the session. Accessing the SSO endpoint with the session cookie set should
      # automatically redirect to the target URL with a JWT; there must be no new session
      # cookie in the response.
      clear_cookies
      url = Addressable::URI.parse('/v3/sso')
      url.query_values = { 'return_to' => 'https://session_test.example.com' }
      set_cookie "#{PUAVO_SSO_SESSION_KEY}=#{session_key}"
      get url.to_s, {}, { 'HTTP_HOST' => 'api.puavo.net' }

      assert_equal last_response.status, 302
      assert_equal last_response.headers.include?('Location'), true
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false

      # Extract and verify the JWT again
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      jwt = JWT.decode(redirect.query_values['jwt'], @external_service2.puavoServiceSecret)[0]

      assert_equal 'bob', jwt['username']
      assert_equal 'Bob', jwt['first_name']
      assert_equal 'Brown', jwt['last_name']
      assert_equal 'student', jwt['user_type']
      assert_equal 'bob@example.com', jwt['email']
      assert_equal 'Example Organisation', jwt['organisation_name']
      assert_equal 'example.puavo.net', jwt['organisation_domain']
      assert_equal '/', jwt['external_service_path_prefix']
      assert_equal @school.puavoId.to_s, jwt['primary_school_id']
    end

    it 'a service that does not have sessions enabled must not return a session cookie' do
      clear_cookies

      post '/v3/sso', {
        'username' => 'bob',
        'password' => 'secret',
        'organisation' => 'example.puavo.net',
        'return_to' => 'https://test-client-service.example.com'
      }

      # A normal redirect without a cookie
      assert_equal last_response.status, 302
      assert_equal last_response.headers.include?('Location'), true
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false

      # We still get the JWT
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      jwt = JWT.decode(redirect.query_values['jwt'], @external_service.puavoServiceSecret)[0]

      assert_equal 'bob', jwt['username']
      assert_equal 'Bob', jwt['first_name']
      assert_equal 'Brown', jwt['last_name']
      assert_equal 'student', jwt['user_type']
      assert_equal 'bob@example.com', jwt['email']
      assert_equal 'Example Organisation', jwt['organisation_name']
      assert_equal 'example.puavo.net', jwt['organisation_domain']
      assert_equal '/', jwt['external_service_path_prefix']
      assert_equal @school.puavoId.to_s, jwt['primary_school_id']
    end

    it 'fake session key will fail' do
      clear_cookies

      url = Addressable::URI.parse('/v3/sso')
      url.query_values = { 'return_to' => 'https://session_test.example.com' }
      set_cookie "#{PUAVO_SSO_SESSION_KEY}=foobar"    # definitely not a valid key
      get url.to_s, {}, { 'HTTP_HOST' => 'api.puavo.net' }

      # The response must be the SSO login form
      assert_equal last_response.status, 401
      assert_equal last_response.headers.include?('Location'), false
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false
      assert_equal last_response.body.include?('Login to service <span>Service with SSO sessions</span>'), true
      assert_equal css('form input[name="return_to"]').first.attributes['value'].value, 'https://session_test.example.com'
    end

    it 'session expiration' do
      clear_cookies

      # Step 1: Acquire a session key
      post '/v3/sso', {
        'username' => 'bob',
        'password' => 'secret',
        'organisation' => 'example.puavo.net',
        'return_to' => 'https://session_test.example.com'
      }

      assert_equal last_response.status, 302
      assert_equal last_response.headers.include?('Location'), true
      assert_equal last_response.headers.include?('Set-Cookie'), true
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), true
      session_key = last_response.cookies[PUAVO_SSO_SESSION_KEY][0]

      # Extract PuavoID from the JWT
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      jwt = JWT.decode(redirect.query_values['jwt'], @external_service2.puavoServiceSecret)[0]
      puavoid = jwt['puavo_id']

      # Manually delete the Redis session entries. We could use Timecop to fool Ruby code
      # into thinking the session is expired, but we can't trick Redis.
      REDIS_CONNECTION.del("sso_session:user:#{puavoid}")
      REDIS_CONNECTION.del("sso_session:data:#{session_key}")

      clear_cookies
      url = Addressable::URI.parse('/v3/sso')
      url.query_values = { 'return_to' => 'https://session_test.example.com' }
      set_cookie "#{PUAVO_SSO_SESSION_KEY}=#{session_key}"      # the session no longer exists
      get url.to_s, {}, { 'HTTP_HOST' => 'api.puavo.net' }

      # The response must be the SSO login form, since the session login must fail
      assert_equal last_response.status, 401
      assert_equal last_response.headers.include?('Location'), false
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false
      assert_equal last_response.body.include?('Login to service <span>Service with SSO sessions</span>'), true
      assert_equal css('form input[name="return_to"]').first.attributes['value'].value, 'https://session_test.example.com'
    end

    it 'session with custom parameters in the return_to URL' do
      # Step 1: Acquire a session key
      clear_cookies

      post '/v3/sso', {
        'username' => 'bob',
        'password' => 'secret',
        'organisation' => 'example.puavo.net',
        'return_to' => 'https://session_test.example.com?foo=bar&baz=quux'
      }

      assert_equal last_response.status, 302
      assert_equal last_response.headers.include?('Location'), true
      assert_equal last_response.headers.include?('Set-Cookie'), true
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), true
      session_key = last_response.cookies[PUAVO_SSO_SESSION_KEY][0]

      redirect = Addressable::URI.parse(last_response.headers['Location'])

      # Must have the custom parameters in the URL
      assert_equal redirect.query_values.include?('foo'), true
      assert_equal redirect.query_values['foo'], 'bar'
      assert_equal redirect.query_values.include?('baz'), true
      assert_equal redirect.query_values['baz'], 'quux'

      # Quick JWT validation
      jwt = JWT.decode(redirect.query_values['jwt'], @external_service2.puavoServiceSecret)[0]
      assert_equal 'bob', jwt['username']
      assert_equal 'Bob', jwt['first_name']
      assert_equal 'Brown', jwt['last_name']

      # Step 2: Login to the service again, with different parameters
      clear_cookies
      url = Addressable::URI.parse('/v3/sso')
      url.query_values = { 'return_to' => 'https://session_test.example.com?blurf=mangle' }
      set_cookie "#{PUAVO_SSO_SESSION_KEY}=#{session_key}"
      get url.to_s, {}, { 'HTTP_HOST' => 'api.puavo.net' }

      # Validate the redirect. There must be no session cookie.
      assert_equal last_response.status, 302
      assert_equal last_response.body, ''
      assert_equal last_response.headers.include?('Location'), true
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false

      redirect = Addressable::URI.parse(last_response.headers['Location'])

      # Must have the custom parameters in the URL
      assert_equal redirect.query_values.include?('foo'), false
      assert_equal redirect.query_values.include?('baz'), false
      assert_equal redirect.query_values.include?('blurf'), true
      assert_equal redirect.query_values['blurf'], 'mangle'

      # Quick JWT validation
      jwt = JWT.decode(redirect.query_values['jwt'], @external_service2.puavoServiceSecret)[0]
      assert_equal 'bob', jwt['username']
      assert_equal 'Bob', jwt['first_name']
      assert_equal 'Brown', jwt['last_name']
    end
  end

  describe "successful login redirect" do
    before(:each) do
      url = Addressable::URI.parse("/v3/sso")
      url.query_values = { "return_to" => "http://test-client-service.example.com/path?foo=bar" }
      basic_authorize "bob", "secret"
      get url.to_s
      assert last_response.headers["Location"]
      @redirect_url = Addressable::URI.parse(last_response.headers["Location"])
      jwt_decode_data = JWT.decode(
        @redirect_url.query_values["jwt"],
        @external_service.puavoServiceSecret
      )
      @jwt = jwt_decode_data[0] # jwt_decode_data is [payload, header]
    end

    it "redirects to return_to url" do
      assert_equal "test-client-service.example.com", @redirect_url.host
      assert_equal "/path", @redirect_url.path
      assert_equal "http", @redirect_url.scheme
    end

    it "preserves existing query strings" do
      assert_equal "bar" , @redirect_url.query_values["foo"]
    end

    it "adds JSON Web Token (jwt) with user data" do
      assert_equal "bob" , @jwt["username"]
      assert_equal "Bob" , @jwt["first_name"]
      assert_equal "Brown" , @jwt["last_name"]
      assert_equal "student" , @jwt["user_type"]
      assert_equal "bob@example.com", @jwt["email"]
      assert_equal "Example Organisation", @jwt["organisation_name"]
      assert_equal "example.puavo.net", @jwt["organisation_domain"]
      assert_equal "/", @jwt["external_service_path_prefix"]
      assert_equal @school.puavoId.to_s, @jwt["primary_school_id"]

      assert_equal 1, @jwt["schools"].size, "should have one school"

      assert_equal(
        ["student"],
        @jwt["schools"][0]["roles"], "should have a student role"
      )

      assert_equal 1, @jwt["schools"][0]["groups"].size, "should have one group"
      group = @jwt["schools"][0]["groups"][0]
      assert_equal "Group 1", group["name"]
    end
  end

  describe "external service activation" do
    before(:each) do
      activate_organisation_services([])
    end

    it "responds 401 for untrusted and inactive services" do
      url = Addressable::URI.parse("/v3/sso")
      url.query_values = { "return_to" => "http://test-client-service.example.com/path?foo=bar" }
      basic_authorize "bob", "secret"
      get url.to_s
      assert_equal 401, last_response.status
    end

    it "responds 302 when service is activated on user's school" do
      # Activate a school-level service
      @school.puavoActiveService = [@external_service.dn]
      @school.save!

      url = Addressable::URI.parse("/v3/sso")
      url.query_values = { "return_to" => "http://test-client-service.example.com/path?foo=bar" }
      basic_authorize "bob", "secret"
      get url.to_s
      assert_equal 302, last_response.status
    end

    it "responds 302 when service is activated on user's organisation" do
      test_organisation = LdapOrganisation.first # TODO: fetch by name
      test_organisation.puavoActiveService = [@external_service.dn]
      test_organisation.save!
      PuavoRest::Organisation.refresh

      url = Addressable::URI.parse("/v3/sso")
      url.query_values = { "return_to" => "http://test-client-service.example.com/path?foo=bar" }
      basic_authorize "bob", "secret"
      get url.to_s
      assert_equal 302, last_response.status
    end
  end

  describe "login form" do
    before(:each) do
      url = Addressable::URI.parse("/v3/sso")
      url.query_values = { "return_to" => "http://test-client-service.example.com/path" }
      get url.to_s, {}, {
        "HTTP_HOST" => "api.puavo.net"
      }
    end

    it "renders login form with 401 for missing credentials" do
      assert_equal 401, last_response.status, last_response.body
      assert last_response.body.include?("form"), "has login form  #{ last_response.body }"
    end


    describe "login" do
      def decode_jwt
        assert_equal 302, last_response.status, last_response.body
        assert last_response.headers["Location"]
        url = Addressable::URI.parse(last_response.headers["Location"])
        assert url.query_values["jwt"], "has jwt token"

        jwt_decode_data = JWT.decode(url.query_values["jwt"], "this is a shared secret")
        jwt_decode_data[0] # jwt_decode_data is [payload, header]
      end

      it "from post"  do
        post "/v3/sso", {
          "username" => "bob",
          "password" => "secret",
          "organisation" => "example.puavo.net",
          "return_to" => "http://test-client-service.example.com/path"
        }

        claims = decode_jwt
        assert_equal "example.puavo.net", claims["organisation_domain"]
        assert_equal last_response.headers.include?('Set-Cookie'), false
      end

      it "from post using custom organisation"  do
        post "/v3/sso", {
          "username" => "admin",
          "password" => "admin",
          "organisation" => "anotherorg.puavo.net",
          "return_to" => "http://test-client-service.example.com/path"
        }

        claims = decode_jwt
        assert_equal "anotherorg.puavo.net", claims["organisation_domain"]
        assert_equal last_response.headers.include?('Set-Cookie'), false
      end

      it "from post using custom organisation in username"  do
        post "/v3/sso", {
          "username" => "admin@anotherorg.puavo.net",
          "password" => "admin",
          "return_to" => "http://test-client-service.example.com/path"
        }

        claims = decode_jwt
        assert_equal "anotherorg.puavo.net", claims["organisation_domain"]
        assert_equal last_response.headers.include?('Set-Cookie'), false
      end

      it 'same organisation in the URL and in username must work' do
        post '/v3/sso', {
          'username' => 'bob@example.puavo.net',    # intentionally redundant
          'password' => 'secret',
          'organisation' => 'example.puavo.net',
          'return_to' => 'http://test-client-service.example.com/path'
        }

        assert_equal last_response.status, 302

        claims = decode_jwt
        assert_equal 'example.puavo.net', claims['organisation_domain']
        assert_equal last_response.headers.include?('Set-Cookie'), false
      end

      it 'different organisations in the URL and in username must fail' do
        post '/v3/sso', {
          'username' => 'bob@foo.puavo.net',
          'password' => 'secret',
          'organisation' => 'example.puavo.net',
          'return_to' => 'http://test-client-service.example.com/path'
        }

        assert_equal last_response.status, 401
        assert_equal last_response.body.include?('Invalid username'), true
      end
    end

    describe "hidden organisation field" do

      def hidden_organisation_field
        el = css("input[name=organisation]").first
        el.attributes["value"].value if el
      end

      it "is overridden from query string" do
        get "/v3/sso", {
          "organisation" => "anotherorg.puavo.net",
          "return_to" => "http://test-client-service.example.com/path",
        }, {
            "HTTP_HOST" => "example.puavo.net"
        }
        assert_equal "anotherorg.puavo.net", hidden_organisation_field
      end

      it "is not set for non-organisation domains" do
        get "/v3/sso", {
          "return_to" => "http://test-client-service.example.com/path",
        }, {
            "HTTP_HOST" => "login.puavo.net"
        }
        assert_nil hidden_organisation_field
      end


    end

    it "renders form errors on the form"  do
      post "/v3/sso", {
        "username" => "bob",
        "password" => "bad",
        "organisation" => "example.puavo.net",
        "return_to" => "http://test-client-service.example.com/path"
      }

      assert_equal 401, last_response.status
      assert_equal "text/html", last_response.content_type
      assert(
        css("#error").first.content.include?("Bad username"),
        "Error message missing from #{ last_response.body }"
      )
      assert_equal last_response.headers.include?('Set-Cookie'), false
    end

  end

  describe "sub service with path prefix" do
    before(:each) do
      @sub_service = ExternalService.new
      @sub_service.classes = ["top", "puavoJWTService"]
      @sub_service.cn = "Sub Service"
      @sub_service.puavoServiceDomain = "test-client-service.example.com"
      @sub_service.puavoServiceSecret = "other shared secret"
      @sub_service.description = "Description"
      @sub_service.mail = "contact@test-client-service.example.com"
      @sub_service.puavoServicePathPrefix = "/prefix"
      @sub_service.puavoServiceTrusted = false
      @sub_service.save!

      activate_organisation_services([@external_service.dn.to_s, @sub_service.dn.to_s])
    end

    it "does not interfere with the main service" do
      url = Addressable::URI.parse("/v3/sso")
      url.query_values = { "return_to" => "http://test-client-service.example.com/path?foo=bar" }
      basic_authorize "bob", "secret"
      get url.to_s
      assert last_response.headers["Location"]
      @redirect_url = Addressable::URI.parse(last_response.headers["Location"])
      jwt_decode_data = JWT.decode(
        @redirect_url.query_values["jwt"],
        @external_service.puavoServiceSecret
      )
      @jwt = jwt_decode_data[0]         # jwt_decode_data is [payload, header]
      assert_equal "/", @jwt["external_service_path_prefix"]
    end

    it "is served form the prefix" do
      url = Addressable::URI.parse("/v3/sso")
      url.query_values = { "return_to" => "http://test-client-service.example.com/prefix?foo=bar" }
      basic_authorize "bob", "secret"
      get url.to_s
      assert last_response.headers["Location"]
      @redirect_url = Addressable::URI.parse(last_response.headers["Location"])
      jwt_decode_data = JWT.decode(
        @redirect_url.query_values["jwt"],
        @sub_service.puavoServiceSecret
      )
      @jwt = jwt_decode_data[0]         # jwt_decode_data is [payload, header]
      assert_equal "/prefix", @jwt["external_service_path_prefix"]
    end

    it "return_to without a path gets matched to /" do
      url = Addressable::URI.parse("/v3/sso")
      url.query_values = { "return_to" => "http://test-client-service.example.com" }
      basic_authorize "bob", "secret"
      get url.to_s
      assert last_response.headers["Location"]
      @redirect_url = Addressable::URI.parse(last_response.headers["Location"])
      jwt_decode_data = JWT.decode(
        @redirect_url.query_values["jwt"],
        @external_service.puavoServiceSecret
      )
      @jwt = jwt_decode_data[0] # jwt_decode_data is [payload, header]
      assert_equal "/", @jwt["external_service_path_prefix"]
    end
  end

  describe 'verified SSO tests' do
    before(:each) do
      @verified_service = ExternalService.new
      @verified_service.classes = ['top', 'puavoJWTService']
      @verified_service.cn = 'Verified service'
      @verified_service.puavoServiceDomain = 'verified.example.com'
      @verified_service.puavoServiceSecret = 'verified'
      @verified_service.puavoServiceTrusted = true
      @verified_service.save!

      activate_organisation_services([@external_service.dn.to_s, @verified_service.dn.to_s])
    end

    it "Can't access the verified SSO form for the normal service" do
      url = Addressable::URI.parse('/v3/verified_sso')
      url.query_values = { 'return_to' => 'http://test-client-service.example.com/path' }
      get url.to_s

      assert_equal 401, last_response.status
      assert_equal last_response.body.include?('Mismatch between trusted service states. Please contact support and give them this code'), true
    end

    it "Can access the normal SSO form for the normal service" do
      url = Addressable::URI.parse('/v3/sso')
      url.query_values = { 'return_to' => 'http://test-client-service.example.com/path' }
      get url.to_s

      assert_equal 401, last_response.status
      assert !last_response.body.include?('This service requires a verified email address.')
    end

    it "Can't access the non-verified SSO form for the verified service" do
      url = Addressable::URI.parse('/v3/sso')
      url.query_values = { 'return_to' => 'https://verified.example.com/' }
      get url.to_s

      assert_equal 401, last_response.status
      assert_equal last_response.body.include?('Mismatch between trusted service states. Please contact support and give them this code'), true
    end

    it "Can access the verified SSO form for the verified service" do
      url = Addressable::URI.parse('/v3/verified_sso')
      url.query_values = { 'return_to' => 'https://verified.example.com/' }
      get url.to_s

      # The response is always 401 (Unauthorized) even if we just display the form normally and nothing is wrong
      assert_equal 401, last_response.status
      assert last_response.body.include?('Login to service <span>Verified service</span>')
    end

    it 'verified SSO login fails without a verified email address' do
      post '/v3/verified_sso', {
        'username' => 'bob',
        'password' => 'secret',
        'organisation' => 'example.puavo.net',
        'return_to' => 'https://verified.example.com/'
      }

      # The login must fail
      assert_equal 401, last_response.status
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert last_response.body.include?('This service requires a verified email address.')
      assert last_response.body.include?('Please edit your user information and confirm an address</a>, then try loggin in again.')
    end

    it 'verified SSO login succeeds with a verified email address' do
      post '/v3/verified_sso', {
        'username' => 'verified',
        'password' => 'trustno1',
        'organisation' => 'example.puavo.net',
        'return_to' => 'https://verified.example.com/'
      }

      # The login must succeed
      assert_equal 302, last_response.status
      assert_equal last_response.headers.include?('Set-Cookie'), false

      # Verify some basic data in the JWT payload
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      jwt = JWT.decode(redirect.query_values['jwt'], @verified_service.puavoServiceSecret)[0]
      assert jwt['username'] == 'verified' && jwt['email'] == 'verified@example.com'
    end

    it 'verified user can log into a non-verified SSO' do
      post '/v3/sso', {
        'username' => 'verified',
        'password' => 'trustno1',
        'organisation' => 'example.puavo.net',
        'return_to' => 'http://test-client-service.example.com/path'
      }

      # The login must succeed
      assert_equal 302, last_response.status
      assert_equal last_response.headers.include?('Set-Cookie'), false

      # Verify some basic data in the JWT payload
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      jwt = JWT.decode(redirect.query_values['jwt'], @external_service.puavoServiceSecret)[0]
      assert jwt['username'] == 'verified' && jwt['email'] == 'verified@example.com'
    end
  end

  describe 'MFA tests' do
    before(:each) do
      @mfa_user = PuavoRest::User.new(
        first_name: 'Bob',
        last_name: 'Page',
        username: 'bob.page',
        password: 'HpF3WNyvESjgQKftfFbPq5ckqsFoeWzEyKR89UoVpVjhlRYJhK',
        roles: ['admin'],
        school_dns: [@school.dn.to_s],
        mfa_enabled: true,
      )

      @mfa_user.save!

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
            'code' => '987654'
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

    def authenticate_user(return_to: 'https://test-client-service.example.com/')
      post '/v3/sso', {
        'username' => 'bob.page',
        'password' => 'HpF3WNyvESjgQKftfFbPq5ckqsFoeWzEyKR89UoVpVjhlRYJhK',
        'organisation' => 'example.puavo.net',
        'return_to' => return_to
      }
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

    it 'basic successfull MFA login' do
      authenticate_user()

      # Since the user has MFA enabled and we passed the login form with basic auth,
      # the response must contain a redirect into the MFA form. Extract its URL
      # and fetch the form. (Can't just directly go to /v3/mfa, because we need the
      # session token.)
      assert_equal last_response.status, 302
      assert_equal last_response.headers.include?('Location'), true
      assert_equal last_response.body, ''

      mfa_form_path = go_to_mfa_form()

      assert_equal last_response.status, 401    # still 401 even though Kerberos is complete by now
      assert last_response.body.include?('Two-factor authentication has been activated on your account.')

      # Ensure the form's hidden token is the same as in the URL (it's not necessary to validate
      # this, but let's make sure)
      assert_equal css('input[name="token"]').first.attributes['value'].value, mfa_form_path.query_values['token']

      # Now we're in the MFA form. "Fill" and post it.
      post '/v3/mfa', {
        'token' => mfa_form_path.query_values['token'],
        'mfa_code' => '987654',
      }

      # Ensure the check passed. Validate the JWT.
      assert_equal last_response.status, 302
      assert_equal last_response.headers.include?('Location'), true
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      jwt = JWT.decode(redirect.query_values['jwt'], @external_service.puavoServiceSecret)[0]
      assert_equal 'bob.page', jwt['username']
      assert_equal 'Bob', jwt['first_name']
      assert_equal 'Page', jwt['last_name']
      assert_equal 'admin', jwt['user_type']
      assert_nil jwt['email']
      assert_equal 'Example Organisation', jwt['organisation_name']
      assert_equal 'example.puavo.net', jwt['organisation_domain']
      assert_equal '/', jwt['external_service_path_prefix']
      assert_equal @school.puavoId.to_s, jwt['primary_school_id']
    end

    it 'basic failed MFA login' do
      authenticate_user()

      assert_equal last_response.status, 302
      assert_equal last_response.headers.include?('Location'), true
      assert_equal last_response.body, ''

      mfa_form_path = go_to_mfa_form()

      assert_equal last_response.status, 401
      assert last_response.body.include?('Two-factor authentication has been activated on your account.')
      assert_equal css('input[name="token"]').first.attributes['value'].value, mfa_form_path.query_values['token']

      # Use one of the incorrect codes
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
      authenticate_user(return_to: 'https://session_test.example.com')
      assert_equal last_response.status, 302
      assert_equal last_response.headers.include?('Location'), true
      assert_equal last_response.body, ''

      # Fill in the MFA form
      mfa_form_path = go_to_mfa_form()
      assert_equal last_response.status, 401
      assert last_response.body.include?('Two-factor authentication has been activated on your account.')

      post '/v3/mfa', {
        'token' => mfa_form_path.query_values['token'],
        'mfa_code' => '987654',
      }

      # Ensure the check passed. Validate the JWT.
      assert_equal last_response.status, 302
      assert_equal last_response.body, ''
      assert_equal last_response.headers.include?('Location'), true
      assert_equal last_response.headers.include?('Set-Cookie'), true
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), true
      session_key = last_response.cookies[PUAVO_SSO_SESSION_KEY][0]

      redirect = Addressable::URI.parse(last_response.headers['Location'])
      jwt = JWT.decode(redirect.query_values['jwt'], @external_service2.puavoServiceSecret)[0]

      assert_equal 'bob.page', jwt['username']
      assert_equal 'Bob', jwt['first_name']
      assert_equal 'Page', jwt['last_name']
      assert_equal 'admin', jwt['user_type']
      assert_nil jwt['email']
      assert_equal 'Example Organisation', jwt['organisation_name']
      assert_equal 'example.puavo.net', jwt['organisation_domain']
      assert_equal '/', jwt['external_service_path_prefix']
      assert_equal @school.puavoId.to_s, jwt['primary_school_id']

      # The session has been established, so try to use it. There should be no login/MFA forms.
      clear_cookies

      url = Addressable::URI.parse('/v3/sso')
      url.query_values = { 'return_to' => 'https://session_test.example.com' }
      set_cookie "#{PUAVO_SSO_SESSION_KEY}=#{session_key}"
      get url.to_s, {}, { 'HTTP_HOST' => 'api.puavo.net' }

      assert_equal last_response.status, 302
      assert_equal last_response.body, ''
      assert_equal last_response.headers.include?('Location'), true
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false

      # Extract and verify the JWT again
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      jwt = JWT.decode(redirect.query_values['jwt'], @external_service2.puavoServiceSecret)[0]

      assert_equal 'bob.page', jwt['username']
      assert_equal 'Bob', jwt['first_name']
      assert_equal 'Page', jwt['last_name']
      assert_equal 'admin', jwt['user_type']
      assert_nil jwt['email']
      assert_equal 'Example Organisation', jwt['organisation_name']
      assert_equal 'example.puavo.net', jwt['organisation_domain']
      assert_equal '/', jwt['external_service_path_prefix']
      assert_equal @school.puavoId.to_s, jwt['primary_school_id']

      # Try to login to another service with the session, it should fail
      clear_cookies

      url = Addressable::URI.parse('/v3/sso')
      url.query_values = { 'return_to' => 'https://session_test2.example.com' }
      set_cookie "#{PUAVO_SSO_SESSION_KEY}=#{session_key}"
      get url.to_s, {}, { 'HTTP_HOST' => 'api.puavo.net' }

      assert_equal last_response.status, 302
      assert_equal last_response.headers.include?('Location'), true
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false

      redirect = Addressable::URI.parse(last_response.headers['Location'])
      jwt = JWT.decode(redirect.query_values['jwt'], @external_service3.puavoServiceSecret)[0]

      assert_equal 'bob.page', jwt['username']
      assert_equal 'Bob', jwt['first_name']
      assert_equal 'Page', jwt['last_name']
      assert_equal 'admin', jwt['user_type']
      assert_nil jwt['email']
      assert_equal 'Example Organisation', jwt['organisation_name']
      assert_equal 'example.puavo.net', jwt['organisation_domain']
      assert_equal '/', jwt['external_service_path_prefix']
      assert_equal @school.puavoId.to_s, jwt['primary_school_id']
    end

    it 'a failed MFA check must not create an SSO session' do
      # Authenticate
      clear_cookies
      authenticate_user(return_to: 'https://session_test.example.com')
      assert_equal last_response.status, 302
      assert_equal last_response.headers.include?('Location'), true
      assert_equal last_response.body, ''

      # Fill in the MFA form
      mfa_form_path = go_to_mfa_form()
      assert_equal last_response.status, 401
      assert last_response.body.include?('Two-factor authentication has been activated on your account.')

      # Post the form four times with incorrect codes
      ['123456', '234567', '345678', '456789'].each do |code|
        post '/v3/mfa', {
          'token' => mfa_form_path.query_values['token'],
          'mfa_code' => code,
        }

        # Ensure each check fails
        assert_equal last_response.status, 401
        assert_equal last_response.headers.include?('Location'), false
        assert last_response.body.include?('<div id="mfa_invalid_code">Incorrect code</div>')
        assert_equal last_response.headers.include?('Location'), false
        assert_equal last_response.headers.include?('Set-Cookie'), false
        assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false
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

    it 'MFA with custom fields in the return_to URL' do
      clear_cookies
      authenticate_user(return_to: 'https://test-client-service.example.com/?foo=bar&baz=quux')

      # The custom parameters must not be present in the MFA form redirect
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values.include?('foo'), false
      assert_equal redirect.query_values.include?('bar'), false

      mfa_form_path = go_to_mfa_form()

      assert_equal last_response.headers.include?('Location'), false

      post '/v3/mfa', {
        'token' => mfa_form_path.query_values['token'],
        'mfa_code' => '987654',
      }

      # No session
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false

      # Ensure the custom parameters are in the redirect URL
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values.include?('foo'), true
      assert_equal redirect.query_values['foo'], 'bar'
      assert_equal redirect.query_values.include?('baz'), true
      assert_equal redirect.query_values['baz'], 'quux'

      # Quick JWT validation
      jwt = JWT.decode(redirect.query_values['jwt'], @external_service.puavoServiceSecret)[0]
      assert_equal 'bob.page', jwt['username']
      assert_equal 'Bob', jwt['first_name']
      assert_equal 'Page', jwt['last_name']
    end

    it 'MFA with custom fields in the return_to URL, with SSO sessions' do
      # Step 1: Acquire a session
      clear_cookies
      authenticate_user(return_to: 'https://session_test.example.com/?foo=bar&baz=quux')

      # The custom parameters must not be present in the MFA form redirect
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      assert_equal redirect.query_values.include?('foo'), false
      assert_equal redirect.query_values.include?('bar'), false

      mfa_form_path = go_to_mfa_form()
      assert_equal last_response.headers.include?('Location'), false

      post '/v3/mfa', {
        'token' => mfa_form_path.query_values['token'],
        'mfa_code' => '987654',
      }

      # Must have a session
      assert_equal last_response.headers.include?('Location'), true
      assert_equal last_response.headers.include?('Set-Cookie'), true
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), true
      session_key = last_response.cookies[PUAVO_SSO_SESSION_KEY][0]

      redirect = Addressable::URI.parse(last_response.headers['Location'])

      # Must have the custom parameters in the URL
      assert_equal redirect.query_values.include?('foo'), true
      assert_equal redirect.query_values['foo'], 'bar'
      assert_equal redirect.query_values.include?('baz'), true
      assert_equal redirect.query_values['baz'], 'quux'

      # Validate the JWT
      jwt = JWT.decode(redirect.query_values['jwt'], @external_service2.puavoServiceSecret)[0]
      assert_equal 'bob.page', jwt['username']
      assert_equal 'Bob', jwt['first_name']
      assert_equal 'Page', jwt['last_name']

      # Step 2: Use the session. This time use different parameters in the redirect URL.
      # The original parameters must not be present anymore.
      clear_cookies

      url = Addressable::URI.parse('/v3/sso')
      url.query_values = { 'return_to' => 'https://session_test.example.com/?blurf=mangle' }
      set_cookie "#{PUAVO_SSO_SESSION_KEY}=#{session_key}"
      get url.to_s, {}, { 'HTTP_HOST' => 'api.puavo.net' }

      # Validate the redirect
      assert_equal last_response.status, 302
      assert_equal last_response.body, ''
      assert_equal last_response.headers.include?('Location'), true
      assert_equal last_response.headers.include?('Set-Cookie'), false
      assert_equal last_response.cookies.include?(PUAVO_SSO_SESSION_KEY), false

      redirect = Addressable::URI.parse(last_response.headers['Location'])

      # Must have the custom parameters in the URL
      assert_equal redirect.query_values.include?('foo'), false
      assert_equal redirect.query_values.include?('baz'), false
      assert_equal redirect.query_values.include?('blurf'), true
      assert_equal redirect.query_values['blurf'], 'mangle'

      # Quick JWT validation
      jwt = JWT.decode(redirect.query_values['jwt'], @external_service2.puavoServiceSecret)[0]
      assert_equal 'bob.page', jwt['username']
      assert_equal 'Bob', jwt['first_name']
      assert_equal 'Page', jwt['last_name']
    end
  end
end

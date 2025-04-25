
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

    activate_organisation_services([@external_service.dn.to_s])
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
      end

      it "from post using custom organisation in username"  do
        post "/v3/sso", {
          "username" => "admin@anotherorg.puavo.net",
          "password" => "admin",
          "return_to" => "http://test-client-service.example.com/path"
        }

        claims = decode_jwt
        assert_equal "anotherorg.puavo.net", claims["organisation_domain"]
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
      assert JSON.parse(last_response.body)['error']['message'].include?("Mismatch between trusted service states. Please check the URL you're using to display the login form.")
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
      assert JSON.parse(last_response.body)['error']['message'].include?("Mismatch between trusted service states. Please check the URL you're using to display the login form.")
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

      # Verify some basic data in the JWT payload
      redirect = Addressable::URI.parse(last_response.headers['Location'])
      jwt = JWT.decode(redirect.query_values['jwt'], @external_service.puavoServiceSecret)[0]
      assert jwt['username'] == 'verified' && jwt['email'] == 'verified@example.com'
    end
  end
end

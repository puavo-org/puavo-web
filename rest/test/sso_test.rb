
require_relative "./helper"

require "addressable/uri"
require "jwt"

describe PuavoRest::SSO do
  before(:each) do
    @orig_config = CONFIG.dup
    CONFIG.delete("default_organisation_domain")
    CONFIG["bootserver"] = false

    PuavoRest::Organisation.refresh
    Puavo::Test.clean_up_ldap
    FileUtils.rm_rf CONFIG["ltsp_server_data_dir"]

    @external_service = ExternalService.new
    @external_service.classes = ["top", "puavoJWTService"]
    @external_service.cn = "Testing Service"
    @external_service.puavoServiceDomain = "test-client-service.example.com"
    @external_service.puavoServiceSecret = "this is a shared secret"
    @external_service.description = "Description"
    @external_service.mail = "contact@test-client-service.example.com"
    @external_service.puavoServiceTrusted = true
    @external_service.save!

    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor"
    )

    @user = User.new(
      :givenName => "Bob",
      :sn  => "Brown",
      :uid => "bob",
      :puavoEduPersonAffiliation => "student",
      :mail => "bob@example.com"
    )
    @user.set_password "secret"
    @user.puavoSchool = @school.dn
    @user.role_ids = [
      Role.find(:first, :attribute => "displayName", :value => "Maintenance").puavoId
    ]
    @user.save!

  end

  after do
    CONFIG = @orig_config
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

  describe "successful login redirect" do
    before(:each) do
      url = Addressable::URI.parse("/v3/sso")
      url.query_values = { "return_to" => "http://test-client-service.example.com/path?foo=bar" }
      basic_authorize "bob", "secret"
      get url.to_s
      assert last_response.headers["Location"]
      @redirect_url = Addressable::URI.parse(last_response.headers["Location"])
      @jwt = JWT.decode(
        @redirect_url.query_values["jwt"],
        @external_service.puavoServiceSecret
      )
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
      assert !@jwt["user_dn"].to_s.empty?
      assert_equal "bob" , @jwt["username"]
      assert_equal "Bob" , @jwt["first_name"]
      assert_equal "Brown" , @jwt["last_name"]
      assert_equal "student" , @jwt["user_type"]
      assert_equal "bob@example.com" , @jwt["email"]
      assert_equal "Example Organisation", @jwt["organisation_name"]
      assert_equal "www.example.net", @jwt["organisation_domain"]
      assert_equal "/", @jwt["external_service_path_prefix"]
      assert_equal "Gryffindor", @jwt["school_name"]
      assert_equal 1, @jwt["groups"].size, "should have one group"
      assert_equal "Maintenance", @jwt["groups"][0]["name"]
      assert !@jwt["school_id"].to_s.empty?
    end

  end

  describe "external service activation" do
    before(:each) do
      @external_service.puavoServiceTrusted = false
      @external_service.save!
    end

    it "responds 401 for untrusted and inactive services" do
      url = Addressable::URI.parse("/v3/sso")
      url.query_values = { "return_to" => "http://test-client-service.example.com/path?foo=bar" }
      basic_authorize "bob", "secret"
      get url.to_s
      assert_equal 401, last_response.status
    end

    it "responds 302 when service is activated on user's school" do
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
        "HTTP_HOST" => "api.example.net"
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

        JWT.decode(url.query_values["jwt"], "this is a shared secret")
      end

      it "from post"  do
        post "/v3/sso", {
          "username" => "bob",
          "password" => "secret",
          "organisation" => "www.example.net",
          "return_to" => "http://test-client-service.example.com/path"
        }

        claims = decode_jwt
        assert_equal "www.example.net", claims["organisation_domain"]
      end

      it "from post using custom organisation"  do
        post "/v3/sso", {
          "username" => "admin",
          "password" => "admin",
          "organisation" => "anotherorg.example.net",
          "return_to" => "http://test-client-service.example.com/path"
        }

        claims = decode_jwt
        assert_equal "anotherorg.example.net", claims["organisation_domain"]
      end

      it "from post using custom organisation in username"  do
        post "/v3/sso", {
          "username" => "admin@anotherorg.example.net",
          "password" => "admin",
          "return_to" => "http://test-client-service.example.com/path"
        }

        claims = decode_jwt
        assert_equal "anotherorg.example.net", claims["organisation_domain"]
      end

    end

    describe "hidden organisation field" do

      def hidden_organisation_field
        el = css("input[name=organisation]").first
        el.attributes["value"].value if el
      end

      it "is added from hostname" do
        get "/v3/sso", {
          "return_to" => "http://test-client-service.example.com/path",
        }, {
            "HTTP_HOST" => "anotherorg.example.net"
        }
        assert_equal "anotherorg.example.net", hidden_organisation_field
      end

      it "is overridden from query string" do
        get "/v3/sso", {
          "organisation" => "anotherorg.example.net",
          "return_to" => "http://test-client-service.example.com/path",
        }, {
            "HTTP_HOST" => "www.example.net"
        }
        assert_equal "anotherorg.example.net", hidden_organisation_field
      end

      it "is not set for non-organisation domains" do
        get "/v3/sso", {
          "return_to" => "http://test-client-service.example.com/path",
        }, {
            "HTTP_HOST" => "login.example.net"
        }
        assert_equal nil, hidden_organisation_field
      end


    end

    it "renders form errors on the form"  do
      post "/v3/sso", {
        "username" => "bob",
        "password" => "bad",
        "organisation" => "www.example.net",
        "return_to" => "http://test-client-service.example.com/path"
      }

      assert_equal 401, last_response.status
      assert_equal "text/html", last_response.content_type
      assert(
        css(".error").first.content.include?("Bad username"),
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
      @sub_service.puavoServiceTrusted = true
      @sub_service.puavoServicePathPrefix = "/prefix"
      @sub_service.save!
    end

    it "does not interfere with the main service" do
      url = Addressable::URI.parse("/v3/sso")
      url.query_values = { "return_to" => "http://test-client-service.example.com/path?foo=bar" }
      basic_authorize "bob", "secret"
      get url.to_s
      assert last_response.headers["Location"]
      @redirect_url = Addressable::URI.parse(last_response.headers["Location"])
      @jwt = JWT.decode(
        @redirect_url.query_values["jwt"],
        @external_service.puavoServiceSecret
      )
      assert_equal "/", @jwt["external_service_path_prefix"]
    end

    it "is served form the prefix" do
      url = Addressable::URI.parse("/v3/sso")
      url.query_values = { "return_to" => "http://test-client-service.example.com/prefix?foo=bar" }
      basic_authorize "bob", "secret"
      get url.to_s
      assert last_response.headers["Location"]
      @redirect_url = Addressable::URI.parse(last_response.headers["Location"])
      @jwt = JWT.decode(
        @redirect_url.query_values["jwt"],
        @sub_service.puavoServiceSecret
      )
      assert_equal "/prefix", @jwt["external_service_path_prefix"]
    end

    it "return_to without a path gets matched to /" do
      url = Addressable::URI.parse("/v3/sso")
      url.query_values = { "return_to" => "http://test-client-service.example.com" }
      basic_authorize "bob", "secret"
      get url.to_s
      assert last_response.headers["Location"]
      @redirect_url = Addressable::URI.parse(last_response.headers["Location"])
      @jwt = JWT.decode(
        @redirect_url.query_values["jwt"],
        @external_service.puavoServiceSecret
      )
      assert_equal "/", @jwt["external_service_path_prefix"]
    end

  end


end

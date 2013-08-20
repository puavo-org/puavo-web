
require_relative "./helper"

require "addressable/uri"
require "jwt"

describe PuavoRest::SSO do
  before(:each) do
    Puavo::Test.clean_up_ldap
    FileUtils.rm_rf PuavoRest::CONFIG["ltsp_server_data_dir"]
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
        PuavoRest::CONFIG["sso"]["test-client-service.example.com"]
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
      assert_equal "example.opinsys.net", @jwt["organisation_domain"]
      assert_equal "example.opinsys.net", @jwt["organisation_domain"]
    end


  end

  describe "login form" do
    before(:each) do
      url = Addressable::URI.parse("/v3/sso")
      url.query_values = { "return_to" => "http://test-client-service.example.com/path" }
      get url.to_s
    end

    it "renders login form with 401 for missing credentials" do
      assert_equal 401, last_response.status
      assert last_response.body.include?("form"), "has login form  #{ last_response.body }"
    end


    describe "login" do
      def decode_jwt
        assert_equal 302, last_response.status
        assert last_response.headers["Location"]
        url = Addressable::URI.parse(last_response.headers["Location"])
        assert url.query_values["jwt"], "has jwt token"

        JWT.decode(url.query_values["jwt"], "this is a shared secret")
      end

      it "from post"  do
        post "/v3/sso", {
          "username" => "bob",
          "password" => "secret",
          "return_to" => "http://test-client-service.example.com/path"
        }
        claims = decode_jwt
        assert_equal "example.opinsys.net", claims["organisation_domain"]
      end

      it "from post using custom organisation"  do
        post "/v3/sso", {
          "username" => "admin",
          "password" => "admin",
          "organisation" => "anotherorg.opinsys.net",
          "return_to" => "http://test-client-service.example.com/path"
        }

        claims = decode_jwt
        assert_equal "anotherorg.opinsys.net", claims["organisation_domain"]
      end

      it "from post using custom organisation in username"  do
        post "/v3/sso", {
          "username" => "admin@anotherorg.opinsys.net",
          "password" => "admin",
          "return_to" => "http://test-client-service.example.com/path"
        }

        claims = decode_jwt
        assert_equal "anotherorg.opinsys.net", claims["organisation_domain"]
      end

      it "from post using custom organisation in query string"  do
        post "/v3/sso?organisation=anotherorg.opinsys.net", {
          "username" => "admin",
          "password" => "admin",
          "return_to" => "http://test-client-service.example.com/path"
        }

        claims = decode_jwt
        assert_equal "anotherorg.opinsys.net", claims["organisation_domain"]
      end

    end

    it "renders form errors on the form"  do
      post "/v3/sso", {
        "username" => "bob",
        "password" => "bad",
        "return_to" => "http://test-client-service.example.com/path"
      }

      assert_equal 401, last_response.status
      assert_equal "text/html", last_response.content_type
      assert(
        last_response.body.include?("Bad username"),
        "Error message missing from #{ last_response.body }"
      )
    end

  end


end

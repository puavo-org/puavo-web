
require_relative "./helper"

require "addressable/uri"
require "openssl"

describe PuavoRest::RemoteAuth do
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
    get "/v3/remote_auth"
    assert_equal 400, last_response.status
  end

  it "responds 401 for unknown services" do
    url = Addressable::URI.parse("/v3/remote_auth")
    url.query_values = { "return_to" => "http://unknown.example.com/path" }
    get url.to_s
    assert_equal 401, last_response.status
  end

  it "responds 401 for bad credentials" do
    url = Addressable::URI.parse("/v3/remote_auth")
    url.query_values = { "return_to" => "http://test-client-service.example.com/path" }
    basic_authorize "bob", "bad"
    get url.to_s
    assert_equal 401, last_response.status
  end


  describe "successful login redirect" do
    before(:each) do
      url = Addressable::URI.parse("/v3/remote_auth")
      url.query_values = { "return_to" => "http://test-client-service.example.com/path?foo=bar" }
      basic_authorize "bob", "secret"
      get url.to_s
      assert last_response.headers["Location"]
      @redirect_url = Addressable::URI.parse(last_response.headers["Location"])
    end

    it "redirects to return_to url" do
      assert_equal "test-client-service.example.com", @redirect_url.host
      assert_equal "/path", @redirect_url.path
      assert_equal "http", @redirect_url.scheme
    end

    it "preserves existing query strings" do
      assert_equal "bar" , @redirect_url.query_values["foo"]
    end

    it "adds user information" do
      assert_equal "bob" , @redirect_url.query_values["username"]
      assert_equal "Bob" , @redirect_url.query_values["first_name"]
      assert_equal "Brown" , @redirect_url.query_values["last_name"]
      assert_equal "student" , @redirect_url.query_values["user_type"]
      assert_equal "bob@example.com" , @redirect_url.query_values["email"]
      assert_equal "Example Organisation" , @redirect_url.query_values["organisation_name"]
      assert_equal "example.opinsys.net" , @redirect_url.query_values["organisation_domain"]
      assert_equal "example.opinsys.net" , @redirect_url.query_values["organisation_domain"]
    end

    it "adds timestamp" do
      assert @redirect_url.query_values["timestamp"].to_i
    end

    it "builds hmac of user information and timestamp" do

      hmac = OpenSSL::HMAC.new(
        PuavoRest::CONFIG["remote_auth"]["test-client-service.example.com"],
        OpenSSL::Digest::SHA1.new
      )

      @redirect_url.query_values.keys.select{ |k| k != "hmac" }.sort.each do |k|
        hmac.update @redirect_url.query_values[k]
      end

      assert_equal hmac.to_s, @redirect_url.query_values["hmac"]
    end

  end

  describe "login form" do
    before(:each) do
      url = Addressable::URI.parse("/v3/remote_auth")
      url.query_values = { "return_to" => "http://test-client-service.example.com/path" }
      get url.to_s
    end

    it "renders login form with 401 for missing credentials" do
      assert_equal 401, last_response.status
      assert last_response.body.include?("form"), "has login form  #{ last_response.body }"
    end

    it "can login from post"  do
      post "/v3/remote_auth", {
        "username" => "bob",
        "password" => "secret",
        "return_to" => "http://test-client-service.example.com/path"
      }
      assert_equal 302, last_response.status
      assert last_response.headers["Location"]
      url = Addressable::URI.parse(last_response.headers["Location"])
      assert_equal "bob", url.query_values["username"]
      assert_equal "Brown", url.query_values["last_name"]
    end

    it "renders form errors on the form"  do
      post "/v3/remote_auth", {
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

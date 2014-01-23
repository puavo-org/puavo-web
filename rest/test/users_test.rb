require_relative "./helper"

describe PuavoRest::Users do

  IMG_FIXTURE = File.join(File.dirname(__FILE__), "fixtures", "profile.jpg")

  before(:each) do
    Puavo::Test.clean_up_ldap
    FileUtils.rm_rf CONFIG["ltsp_server_data_dir"]
    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor",
      :puavoSchoolHomePageURL => "schoolhomepage.example"
    )

    @user = User.new(
      :givenName => "Bob",
      :sn  => "Brown",
      :uid => "bob",
      :puavoEduPersonAffiliation => "student",
      :preferredLanguage => "en",
      :mail => "bob@example.com"
    )
    @user.set_password "secret"
    @user.puavoSchool = @school.dn
    @user.role_ids = [
      Role.find(:first, :attribute => "displayName", :value => "Maintenance").puavoId
    ]
    @user.save!
  end

  describe "GET /v3/whoami" do
    it "returns information about authenticated user" do
      basic_authorize "bob", "secret"
      get "/v3/whoami"
      assert_200
      data = JSON.parse(last_response.body)

      assert_equal "bob", data["username"]
      assert_equal "Bob", data["first_name"]
      assert_equal "Brown", data["last_name"]
      assert_equal "bob@example.com", data["email"]
      assert_equal "student", data["user_type"]
      assert_equal "en", data["preferred_language"]
      assert data["uid_number"], "has uid number"
      assert data["gid_number"], "has gid number"
      assert_equal Fixnum, data["uid_number"].class, "uid number must be a Fixnum"

      assert data["organisation"], "has organisation data added"

      assert_equal "Example Organisation", data["organisation"]["name"]
      assert_equal "www.example.net", data["organisation"]["domain"]
      assert_equal "dc=edu,dc=example,dc=fi", data["organisation"]["base"]
      assert_equal "bob@www.example.net", data["domain_username"]
      assert_equal "schoolhomepage.example", data["homepage"]

      assert_equal "http://www.example.net/v3/users/bob/profile.jpg", data["profile_image_link"]

    end
  end


  describe "GET /v3/users/bob" do

    it "returns user data" do
      basic_authorize "bob", "secret"
      get "/v3/users/bob"
      assert_200
      data = JSON.parse(last_response.body)

      assert_equal "bob", data["username"]
      assert_equal "Bob", data["first_name"]
      assert_equal "Brown", data["last_name"]
      assert_equal "bob@example.com", data["email"]
      assert_equal "student", data["user_type"]
      assert_equal "http://www.example.net/v3/users/bob/profile.jpg", data["profile_image_link"]
    end

    describe "with language fallbacks" do
      [
        {
          :name   => "user lang is the most preferred",
          :org    => "en",
          :school => "fi",
          :user   => "sv",
          :expect => "sv"
        },
        {
          :name   => "first fallback is school",
          :org    => "en",
          :school => "fi",
          :user   => nil,
          :expect => "fi"
        },
        {
          :name   => "organisation is the least preferred",
          :org    => "en",
          :school => nil,
          :user   => nil,
          :expect => "en"
        },
      ].each do |opts|
        it opts[:name] do
          @user.preferredLanguage = opts[:user]
          @user.save!
          @school.preferredLanguage = opts[:school]
          @school.save!

          test_organisation = LdapOrganisation.first # TODO: fetch by name
          test_organisation.preferredLanguage = opts[:org]
          test_organisation.save!

          basic_authorize "bob", "secret"
          get "/v3/users/bob"
          assert_200
          data = JSON.parse(last_response.body)
          assert_equal opts[:expect], data["preferred_language"]
        end
      end
    end

    describe "with image" do
      before(:each) do
        @user.image = Rack::Test::UploadedFile.new(IMG_FIXTURE, "image/jpeg")
        @user.save!
      end

      it "returns user data with image link" do
        basic_authorize "bob", "secret"
        get "/v3/users/bob"
        assert_200
        data = JSON.parse(last_response.body)

        assert_equal "http://www.example.net/v3/users/bob/profile.jpg", data["profile_image_link"]
      end

      it "can be faked with VirtualHostBase" do
        basic_authorize "bob", "secret"
        get "/VirtualHostBase/http/fakedomain:1234/v3/users/bob"
        assert_200
        data = JSON.parse(last_response.body)

        assert_equal "http://fakedomain:1234/v3/users/bob/profile.jpg", data["profile_image_link"]
      end

      it "does not have 443 in uri if https" do
        basic_authorize "bob", "secret"
        get "/VirtualHostBase/https/fakedomain:443/v3/users/bob"
        assert_200
        data = JSON.parse(last_response.body)

        assert_equal "https://fakedomain/v3/users/bob/profile.jpg", data["profile_image_link"]
      end

    end

    it "returns 401 without auth" do
      get "/v3/users/bob"
      assert_equal 401, last_response.status, last_response.body
      assert_equal "Negotiate", last_response.headers["WWW-Authenticate"], "WWW-Authenticate must be Negotiate for kerberos to work"
    end

    it "returns 401 with bad auth" do
      basic_authorize "bob", "bad"
      get "/v3/users/bob"
      assert_equal 401, last_response.status, last_response.body
    end
  end

  describe "GET /v3/users/bob/profile.jpg" do

    it "returns 200 if bob hash image" do
      @user.image = Rack::Test::UploadedFile.new(IMG_FIXTURE, "image/jpeg")
      @user.save!

      basic_authorize "bob", "secret"
      get "/v3/users/bob/profile.jpg"
      assert_200
      assert last_response.body.size > 10
    end

    it "returns 404 if bob has no image" do
      basic_authorize "bob", "secret"
      get "/v3/users/bob/profile.jpg"

      assert_equal 404, last_response.status, last_response.body
      assert_equal({
        "error" => {
          "code" => "NotFound",
          "message" => "bob has no profile image"
        }
      },
        JSON.parse(last_response.body)
      )
    end

    it "returns 401 without auth" do
      get "/v3/users/bob/profile.jpg"
      assert_equal 401, last_response.status, last_response.body
    end

  end

end

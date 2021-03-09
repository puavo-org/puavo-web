require_relative "./helper"

describe PuavoRest::Users do

  IMG_FIXTURE = File.join(File.dirname(__FILE__), "fixtures", "profile.jpg")

  before(:each) do
    Puavo::Test.clean_up_ldap
    setup_ldap_admin_connection()

    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor",
      :puavoSchoolHomePageURL => "schoolhomepage.example"
    )

    @group = PuavoRest::Group.new(
      :abbreviation => 'group1',
      :name         => 'Group 1',
      :school_dn    => @school.dn.to_s,
      :type         => 'teaching group')
    @group.save!

    @maintenance_group = Group.find(:first,
                                    :attribute => 'cn',
                                    :value     => 'maintenance')
    @teacher = PuavoRest::User.new(
      :email            => 'bob@example.com',
      :external_id      => 'bob',
      :first_name       => 'Bob',
      :last_name        => 'Brown',
      :locale           => 'en_US.UTF-8',
      :password         => 'secret',
      :roles            => [ 'teacher' ],
      :school_dns       => [ @school.dn.to_s ],
      :telephone_number => [ '123', '456' ],
      :ssh_public_key   => 'asdfsdfdfsdfwersSSH_PUBLIC_KEYfdsasdfasdfadf',
      :username         => 'bob',
    )
    @teacher.save!

    # XXX weird that these must be here:
    @teacher.administrative_groups = [ @maintenance_group.id ]
    @teacher.secondary_emails = [ 'bob@foobar.com', 'bob@helloworld.com' ]
    @teacher.teaching_group = @group
    @teacher.save!

    @user2 = PuavoRest::User.new(
      :email            => 'alice@example.com',
      :first_name       => 'Alice',
      :last_name        => 'Wonder',
      :locale           => 'en_US.UTF-8',
      :password         => 'secret',
      :roles            => [ 'student' ],
      :school_dns       => [ @school.dn.to_s ],
      :telephone_number => [ '789' ],
      :username         => 'alice',
    )
    @user2.save!

    # XXX weird that these must be here
    @user2.administrative_groups = [ @maintenance_group.id ]
    @user2.teaching_group = @group

    @user4 = PuavoRest::User.new(
      :first_name => 'Joe',
      :last_name  => 'Bloggs',
      :locale     => 'en_US.UTF-8',
      :password   => 'secret',
      :roles      => [ 'admin' ],
      :school_dns => [ @school.dn.to_s ],
      :username   => 'joe.bloggs',
    )
    @user4.save!
    # to use .add_admin() must use the puavo-web object
    _user4 = User.find(:first, :attribute => 'puavoId', :value => @user4.id)
    @school.add_admin(_user4)

    @user5 = PuavoRest::User.new(
      :do_not_delete => 'TRUE',
      :first_name    => 'Poistettava',
      :last_name     => 'Käyttäjä',
      :password      => 'trustno1',
      :roles         => [ 'testuser' ],
      :school_dns    => [ @school.dn.to_s ],
      :username      => 'poistettava.kayttaja',
    )
    @user5.save!
  end

  describe "Multiple telephone numbers" do
    it "correctly set when a user is created" do
      assert_equal [ '123', '456' ], @teacher.telephone_number
      assert_equal [ '789' ], @user2.telephone_number
      assert_equal [], @user4.telephone_number
    end

    it "can be changed" do
      @teacher.telephone_number = [ '1234567890' ]
      @teacher.save!
      assert_equal [ '1234567890' ], @teacher.telephone_number
    end

    it "can be cleared" do
      @teacher.telephone_number = []
      @teacher.save!
      @user2.telephone_number = nil
      @user2.save!
      assert_equal [], @teacher.telephone_number
      assert_equal [], @user2.telephone_number
    end
  end

  describe "User deletion" do
    it "user cannot delete itself" do
      basic_authorize "poistettava.kayttaja", "trustno1"
      delete "/v3/users/poistettava.kayttaja"
      assert_equal 403, last_response.status
    end

    it "user cannot mark themselves for deletion" do
      basic_authorize "poistettava.kayttaja", "trustno1"
      put "/v3/users/poistettava.kayttaja/mark_for_deletion"
      assert_equal 403, last_response.status
    end

    it "non-admin cannot delete someone else" do
      basic_authorize "poistettava.kayttaja", "trustno1"
      delete "/v3/users/bob"
      assert_equal 404, last_response.status
    end

    it "admin can delete user" do
      # TODO: Bob must be an organisation owner in order to do this!

      #@teacher.puavoEduPersonAffiliation = ["admin"]
      #@teacher.save!
      #@school.add_admin(@teacher)
      #basic_authorize "bob", "secret"
      #delete "/v3/users/poistettava.kayttaja"
      #assert_equal 200, last_response.status
    end
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
      assert_equal "Example Organisation", data["organisation_name"]
      assert_equal "example.puavo.net", data["organisation_domain"]
    end
  end

  describe "GET /v3/users" do
    it "lists all users" do
      basic_authorize "bob", "secret"
      get "/v3/users"
      assert_200
      data = JSON.parse(last_response.body)

      alice = data.select do |u|
        u["username"] == "alice"
      end.first

      assert(alice)
      assert_equal("Alice", alice["first_name"])
      assert_equal("Wonder", alice["last_name"])

      assert(data.select do |u|
        u["username"] == "bob"
      end.first)
    end

    it "lists all users with attribute limit" do
      basic_authorize "bob", "secret"
      get "/v3/users?attributes=username,first_name"
      assert_200
      data = JSON.parse(last_response.body)

      alice = data.select do |u|
        u["username"] == "alice"
      end.first

      assert(alice)
      assert_equal("Alice", alice["first_name"])
      assert_nil(alice["last_name"])

      assert(data.select do |u|
        u["username"] == "bob"
      end.first)
    end


  end

  describe "external ID tests" do
    it "can save a user without changing anything" do
      assert @teacher.save!
    end

    it "can save a user while 'changing' external ID" do
      @teacher.external_id = 'bob'
      assert @teacher.save!
    end

    it "can actually change the external ID" do
      @teacher.external_id = 'paavo'
      assert @teacher.save!
    end

    it "give user a new external ID" do
      @user2.external_id = 'alice'
      assert @user2.save!
    end

    it "cannot reuse existing external ID" do
      # try to reuse Bob's external ID
      @user2.external_id = 'bob'

      exception = assert_raises ValidationError do
        assert @user2.save!
      end

      assert exception.message.match(/external_id=bob is not unique/)
    end
  end

  describe "GET /v3/users/_by_id/" do
    it "returns user data" do
      basic_authorize "bob", "secret"
      get "/v3/users/_by_id/#{ @teacher.id }"
      assert_200
      data = JSON.parse(last_response.body)

      assert_equal "bob", data["username"]
      assert_equal "Bob", data["first_name"]
      assert_equal "Brown", data["last_name"]
    end

    it "reverse name is updated if user's name is changed" do
      @teacher.first_name = 'Bob'
      @teacher.last_name = 'Brown'
      @teacher.save!

      basic_authorize "bob", "secret"
      get "/v3/users/_by_id/#{ @teacher.id }"
      assert_200
      data = JSON.parse(last_response.body)

      assert_equal "bob", data["username"]
      assert_equal "Bob", data["first_name"]
      assert_equal "Brown", data["last_name"]
      assert_equal "Brown Bob", data["reverse_name"]
    end

    it "whitespace in email addresses is really removed" do
      # XXX this test perhaps does not belong to puavo-rest tests
      # XXX because puavo-rest does *not* strip whitespace
      _teacher = User.find(:first,
                           :attribute => 'puavoId',
                           :value     => @teacher.id)
      _teacher.mail = " foo.bar@baz.com     "
      _teacher.save!

      basic_authorize "bob", "secret"
      get "/v3/users/_by_id/#{ @teacher.id }"
      assert_200
      data = JSON.parse(last_response.body)

      assert_equal "foo.bar@baz.com", data["email"]
    end
  end

  describe "GET /v3/users/bob" do
    it "organisation owner can see ssh_public_key of bob" do
      basic_authorize "cucumber", "cucumber"
      get "/v3/users/bob"
      assert_200
      data = JSON.parse(last_response.body)

      assert_equal "bob", data["username"]
      assert_equal "Bob", data["first_name"]
      assert_equal "asdfsdfdfsdfwersSSH_PUBLIC_KEYfdsasdfasdfadf", data["ssh_public_key"]
    end

    it "returns user data" do
      basic_authorize "bob", "secret"
      get "/v3/users/bob"
      assert_200
      data = JSON.parse(last_response.body)

      assert_equal "bob", data["username"]
      assert_equal "Bob", data["first_name"]
      assert_equal "Brown", data["last_name"]
      assert_equal "bob@example.com", data["email"]
      assert_equal [ "bob@foobar.com", "bob@helloworld.com" ],
                   data["secondary_emails"]
      assert_equal "teacher", data["user_type"]
      assert_equal "http://example.puavo.net/v3/users/bob/profile.jpg",
                   data["profile_image_link"]

      assert data["schools"], "has schools data added"
      assert_equal(1, data["schools"].size)
    end

    describe "with language fallbacks" do
      [
        {
          :expect_language => "sv",
          :expect_locale   => "sv_FI.UTF-8",
          :name            => "user lang is the most preferred",
          :org             => "en_US.UTF-8",
          :school_lang     => "fi",
          :school_locale   => "fi_FI.UTF-8",
          :user_lang       => "sv",
          :user_locale     => "sv_FI.UTF-8",
        },
        {
          :expect_language => "fi",
          :expect_locale   => "fi_FI.UTF-8",
          :name            => "first fallback is school",
          :org             => "en_US.UTF-8",
          :school_lang     => "fi",
          :school_locale   => "fi_FI.UTF-8",
          :user_lang       => nil,
          :user_locale     => nil,
        },
        {
          :expect_language => "en",
          :expect_locale   => "en_US.UTF-8",
          :name            => "organisation is the least preferred",
          :org             => "en_US.UTF-8",
          :school_lang     => nil,
          :school_locale   => nil,
          :user_lang       => nil,
          :user_locale     => nil,
        },
      ].each do |opts|
        it opts[:name] do
          @teacher.locale = opts[:user_locale]
          @teacher.preferred_language = opts[:user_lang]
          @teacher.save!
          @school.preferredLanguage = opts[:school_lang]
          @school.puavoLocale = opts[:school_locale]
          @school.save!

          test_organisation = LdapOrganisation.first # TODO: fetch by name
          test_organisation.puavoLocale = opts[:org]
          test_organisation.save!

          basic_authorize "bob", "secret"
          get "/v3/users/bob"
          assert_200
          data = JSON.parse(last_response.body)
          assert_equal opts[:expect_language], data["preferred_language"]
          assert_equal opts[:expect_locale], data["locale"]
        end
      end
    end

    describe "with image" do
      before(:each) do
        _teacher = User.find(:first,
                             :attribute => 'puavoId',
                             :value     => @teacher.id)
        _teacher.image = Rack::Test::UploadedFile.new(IMG_FIXTURE, "image/jpeg")
        _teacher.save!
      end

      it "returns user data with image link" do
        basic_authorize "bob", "secret"
        get "/v3/users/bob"
        assert_200
        data = JSON.parse(last_response.body)

        assert_equal "http://example.puavo.net/v3/users/bob/profile.jpg",
                     data["profile_image_link"]
      end

      it "can be faked with VirtualHostBase" do
        basic_authorize "bob", "secret"
        get "/VirtualHostBase/http/fakedomain:1234/v3/users/bob"
        assert_200
        data = JSON.parse(last_response.body)

        assert_equal "http://fakedomain:1234/v3/users/bob/profile.jpg",
                     data["profile_image_link"]
      end

      it "does not have 443 in uri if https" do
        basic_authorize "bob", "secret"
        get "/VirtualHostBase/https/fakedomain:443/v3/users/bob"
        assert_200
        data = JSON.parse(last_response.body)

        assert_equal "https://fakedomain/v3/users/bob/profile.jpg",
                     data["profile_image_link"]
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
      _teacher = User.find(:first,
                           :attribute => 'puavoId',
                           :value     => @teacher.id)
      _teacher.image = Rack::Test::UploadedFile.new(IMG_FIXTURE, "image/jpeg")
      _teacher.save!

      basic_authorize "bob", "secret"
      get "/v3/users/bob/profile.jpg"
      assert_200
      assert last_response.body.size > 10
    end

    it "returns the default anonymous image if bob has no image" do
      basic_authorize "bob", "secret"
      get "/v3/users/bob/profile.jpg"
      assert_200

      img_data = File.read(PuavoRest::Users::ANONYMOUS_IMAGE_PATH)
      hash = Digest::MD5.hexdigest(img_data)

      assert_equal(hash, Digest::MD5.hexdigest(last_response.body))
    end

    it "returns 401 without auth" do
      get "/v3/users/bob/profile.jpg"
      assert_equal 401, last_response.status, last_response.body
    end

  end

  describe "groups" do
    it "can be listed" do
      user = PuavoRest::User.by_username(@teacher.username)
      group_names = Set.new(user.groups.map{ |g| g.name })
      assert !group_names.include?("Gryffindor"), "Group list must not include schools"

      assert_equal(
        Set.new(["Maintenance", "Group 1"]),
        group_names
      )
    end
  end

  describe "GET /v3/users/_search" do

    before(:each) do
      @user3 = PuavoRest::User.new(
        :email      => 'alice.another@example.com',
        :first_name => 'Alice',
        :last_name  => 'Another',
        :locale     => 'en_US.UTF-8',
        :password   => 'secret',
        :roles      => [ 'student' ],
        :school_dns => [ @school.dn.to_s ],
        :username   => 'alice.another',
      )
      @user3.save!

      # XXX weird that this must be here
      @user3.administrative_groups = [ @maintenance_group.id ]
    end

    it "can list bob" do
      basic_authorize "bob", "secret"
      get "/v3/users/_search?q=bob"
      assert_200
      data = JSON.parse(last_response.body)

      bob = data.select do |u|
        u["username"] == "bob"
      end.first

      assert bob

      assert bob["schools"], "has schools data added"
      assert_equal(1, bob["schools"].size)
    end

    it "can find bob with a partial match" do
      basic_authorize "bob", "secret"
      get "/v3/users/_search?q=bro"
      assert_200
      data = JSON.parse(last_response.body)

      bob = data.select do |u|
        u["username"] == "bob"
      end

      assert_equal 1, bob.size
    end

    it "can all alices" do
      basic_authorize "bob", "secret"
      get "/v3/users/_search?q=alice"
      assert_200
      data = JSON.parse(last_response.body)
      assert_equal 2, data.size, data
    end

    it "can limit search with multiple keywords" do
      basic_authorize "bob", "secret"
      get "/v3/users/_search?q=alice+Wonder"
      assert_200
      data = JSON.parse(last_response.body)
      assert_equal 1, data.size, data
      assert_equal "alice", data[0]["username"]
    end

    it "can find alice by email" do
      basic_authorize "cucumber", "cucumber"
      get "/v3/users/_search?q=alice@example.com"
      assert_200
      data = JSON.parse(last_response.body)
      assert_equal 1, data.size, data
      assert_equal "alice", data[0]["username"]
    end

  end


  describe "PUT /v3/users/:username/administrative_groups" do

    before(:each) do
      @user3 = PuavoRest::User.new(
        :first_name => "Jane",
        :last_name => "Doe",
        :username => "jane.doe",
        :roles => ["student"],
        :school_dns => [@school.dn.to_s]
      )
      @user3.save!

      @group2 = PuavoRest::Group.new(
        :abbreviation => 'testgroup2',
        :name         => 'Test group 2',
        :school_dn    => @school.dn.to_s,
        :type         => 'administrative group',
      )
      @group2.save!
    end

    it "update administrative groups for user" do

      basic_authorize "joe.bloggs", "secret"

      put "/v3/users/#{ @user3.username }/administrative_groups",
        "ids" => [ @group2.id ]
      assert_200

      get "/v3/users/#{ @user3.username }/administrative_groups"
      assert_200
      data = JSON.parse(last_response.body)

      assert data[0]["member_usernames"].include?(@user3.username), "#{ @user3.username } is not member of group"
    end
  end

end

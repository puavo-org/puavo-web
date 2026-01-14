require_relative "./helper"
require_relative "../lib/ldapmodel"

describe LdapModel do

  describe "user validation" do

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

      @user = PuavoRest::User.new(
        :email      => 'heli.kopteri@example.com',
        :first_name => 'Heli',
        :last_name  => 'Kopteri',
        :password   => 'userpw',
        :roles      => [ 'staff' ],
        :school_dns => [ @school.dn.to_s ],
        :username   => 'heli',
      )
      @user.save!
      @user.teaching_group = @group   # XXX weird that this must be here
    end

    it "cannot create users with the same usernames" do
      user = PuavoRest::User.new(
        :first_name => "Heli",
        :last_name => "Kopteri",
        :username => "heli",
        :roles => ["staff"],
        :email => "heli.kopteri2@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "userpw",

        :login_shell => "/bin/bash"
      )

      err = assert_raises ValidationError do
        user.save!
      end

      username_error = err.as_json[:error][:meta][:invalid_attributes][:username].first
      assert username_error
      assert_equal :username_not_unique, username_error[:code]
      assert_equal "username=heli is not unique", username_error[:message]
      assert_equal @user.id, PuavoRest::IdPool.last_id("puavoNextId").to_i

    end

    it "model can be validated only" do
      user = PuavoRest::User.new(
        :first_name => "Heli",
        :last_name => "Kopteri",
        :username => "heli",
        :roles => ["staff"],
        :email => "heli.kopteri@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "userpw"
      )

      err = assert_raises ValidationError do
        user.validate!
      end

      username_error = err.as_json[:error][:meta][:invalid_attributes][:username].first
      assert username_error
      assert_equal :username_not_unique, username_error[:code]
      assert_equal "username=heli is not unique", username_error[:message]
    end

    it "on successful validation the model is not saved" do
      user = PuavoRest::User.new(
        :first_name => "Foo",
        :last_name => "Bar",
        :username => "foo",
        :roles => ["staff"],
        :email => "foo@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "userpw"
      )

      user.validate!
      assert !PuavoRest::User.by_username("foo"), "the user cannot be found because it is not saved"
    end

    it "can be accessed over http" do
      basic_authorize "heli", "userpw"
      post "/v3/users_validate", {
        :first_name => "Heli",
        :last_name => "Kopteri",
        :username => "heli",
        :roles => ["staff"],
        :email => "heli.kopteri@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "userpw"
      }

      assert_equal 400, last_response.status
      data = JSON.parse last_response.body
      assert_equal "ValidationError", data["error"]["code"]

      assert(
        data["error"]["meta"]["invalid_attributes"]["username"],
        "username is duplicate"
      )
      assert_equal(
        "username_not_unique",
        data["error"]["meta"]["invalid_attributes"]["username"][0]["code"]
      )

      assert(
        data["error"]["meta"]["invalid_attributes"]["email"],
        "email is duplicate"
      )
      assert_equal(
        "email_not_unique",
        data["error"]["meta"]["invalid_attributes"]["email"][0]["code"]
      )

    end

    it "does not allow empty first name" do
      user = PuavoRest::User.new(
        :last_name => "Bar",
        :username => "foo",
        :roles => ["staff"],
        :email => "foo@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "userpw"
      )

      err = assert_raises ValidationError do
        user.validate!
      end

      first_name_error = err.as_json[:error][:meta][:invalid_attributes][:first_name].first
      assert first_name_error
      assert_equal :first_name_empty, first_name_error[:code]
      assert_equal "First name is empty", first_name_error[:message]
    end

    it "does not allow empty last name" do
      user = PuavoRest::User.new(
        :first_name => "Foo",
        :username => "foo",
        :roles => ["staff"],
        :email => "foo@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "userpw"
      )

      err = assert_raises ValidationError do
        user.validate!
      end

      error = err.as_json[:error][:meta][:invalid_attributes][:last_name].first
      assert error
      assert_equal :last_name_empty, error[:code]
      assert_equal "Last name is empty", error[:message]
    end

    it "do not allow 'root' as username" do
      user = PuavoRest::User.new(
        :first_name => "Foo",
        :last_name => "Bar",
        :username => "root",
        :roles => ["staff"],
        :email => "foo@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "sdafdsdfsadfsadsf"
      )

      err = assert_raises ValidationError do
        user.validate!
      end

      error = err.as_json[:error][:meta][:invalid_attributes][:username].first
      assert error
      assert_equal :username_not_allowed, error[:code]
      assert_equal "Username not allowed", error[:message]
    end

    [ # deny these
      "1foo",
      "Foo",
      "foo bar",
      "-foo",
      ".foo",
      "foo_bar",
      "FOO",
    ].each do |invalid_username|
      it "denies invalid username '#{ invalid_username }'" do
        user = PuavoRest::User.new(
          :first_name => "Foo",
          :last_name => "Bar",
          :username => invalid_username,
          :roles => ["staff"],
          :email => "foo@example.com",
          :school_dns => [@school.dn.to_s],
          :password => "sdafdsdfsadfsadsf"
        )

        err = assert_raises ValidationError do
          user.validate!
        end

        error = err.as_json[:error][:meta][:invalid_attributes][:username].first
        assert error, "must not allow username '#{ invalid_username }'"
        assert_equal :username_invalid, error[:code]
        assert_equal "Invalid username.  Allowed characters a-z, 0-9, underscore, dot and dash.  Also it must begin with a letter.", error[:message]
      end

    end


    it "do not allow too short username" do
      user = PuavoRest::User.new(
        :first_name => "Foo",
        :last_name => "Bar",
        :username => "ba",
        :roles => ["staff"],
        :email => "foo@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "sdafdsdfsadfsadsf"
      )

      err = assert_raises ValidationError do
        user.validate!
      end

      error = err.as_json[:error][:meta][:invalid_attributes][:username].first
      assert error
      assert_equal :username_too_short, error[:code]
      assert_equal "Username too short", error[:message]

    end

    it "do not allow too long username" do
      user = PuavoRest::User.new(
        :first_name => "Foo",
        :last_name => "Bar",
        :username => "a"*300,
        :roles => ["staff"],
        :email => "foo@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "sdafdsdfsadfsadsf"
      )

      err = assert_raises ValidationError do
        user.validate!
      end

      error = err.as_json[:error][:meta][:invalid_attributes][:username].first
      assert error
      assert_equal :username_too_long, error[:code]
      assert_equal "Username too long", error[:message]

    end

    it "can't set '-' as the telephone number of an existing user" do
      @user.telephone_number = [ ' - ' ]

      error = assert_raises ValidationError do
        @user.save!
      end

      error = error.as_json[:error][:meta][:invalid_attributes][:telephone_number].first
      assert error
      assert_equal :telephone_number_invalid, error[:code]
      assert_equal "A telephone number cannnot be just a '-'", error[:message]
    end
  end
end

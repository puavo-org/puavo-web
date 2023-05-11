require_relative "./helper"

describe LdapModel do

  describe "user creation" do

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
        # must be student, since year classes are NOT saved for non-students!
        :roles      => [ 'student' ],
        :school_dns => [ @school.dn.to_s ],
        :username   => 'heli',
      )
      @user.save!

      @teaching_group = PuavoRest::Group.new(
        :abbreviation => 'gryffindor-5a',
        :name         => '5A',
        :school_dn    => @school.dn.to_s,
        :type         => 'teaching group',
      )
      @teaching_group.save!

      @year_class = PuavoRest::Group.new(
        :abbreviation => 'gryffindor-5',
        :name         => '5',
        :school_dn    => @school.dn.to_s,
        :type         => 'year class',
      )
      @year_class.save!
    end

    it "has Integer id" do
      # FIXME: should be String
      assert_equal Integer, @user.id.class
    end

    it "has dn" do
      assert @user.dn, "model got dn"
    end

    it "has email" do
      assert_equal @user.email, ["heli.kopteri@example.com"]
    end

    it "has home directory" do
      assert_equal "/home/heli", @user.home_directory
    end

    it "has gid_number from school" do
      assert_equal @school.gidNumber, @user.gid_number
    end

    it "has displayName ldap value" do
      assert_equal ["Heli Kopteri"], @user.get_raw(:displayName)
    end

    it "can be fetched by dn" do
      assert PuavoRest::User.by_dn!(@user.dn), "model can be found by dn"
    end

    it "has school" do
      assert_equal "Gryffindor", @user.schools.first.name
    end

    it "Can't use '-' as a phone number" do
      user = PuavoRest::User.new(
        :username   => 'phone.number',
        :first_name => 'Phone',
        :last_name  => 'Number',
        :telephone_number => '-',
        :roles      => ['student'],
        :school_dns => [@school.dn.to_s],
      )

      error = assert_raises ValidationError do
        user.save!
      end

      error = error.as_json[:error][:meta][:invalid_attributes][:telephone_number].first
      assert error
      assert_equal :telephone_number_invalid, error[:code]
      assert_equal "A telephone number cannnot be just a '-'", error[:message]
    end

    it "has internal samba attributes" do
      assert_equal ["[U]"], @user.get_raw(:sambaAcctFlags)

      samba_sid = @user.get_raw(:sambaSID)
      assert samba_sid
      assert samba_sid.first
      assert_equal "S", samba_sid.first.first

      samba_primary_group_sid = @user.get_raw(:sambaSID)
      assert samba_primary_group_sid
      assert samba_primary_group_sid.first
      assert_equal "S", samba_primary_group_sid.first.first

      samba_group = PuavoRest::SambaGroup.by_attr!(:name, "Domain Users")
      assert(
        samba_group.members.include?(@user.username),
        "Samba group 'Domain users' includes the username"
      )
    end

    it "can clear the email address" do
      user = PuavoRest::User.by_dn!(@user.dn)
      assert_equal user.email, ["heli.kopteri@example.com"]

      user.email = nil
      assert user.save!

      user = PuavoRest::User.by_dn!(@user.dn)
      assert_equal user.email, []
    end

    it "can authenticate using the username and password" do
      basic_authorize "heli", "userpw"
      get "/v3/whoami"
      assert_200
      data = JSON.parse(last_response.body)
      assert_equal "heli", data["username"]
    end

    it "can change the password" do
      user = PuavoRest::User.by_dn!(@user.dn)
      user.password = "newpw"
      user.save!

      basic_authorize "heli", "userpw"
      get "/v3/whoami"
      assert_equal 401, last_response.status, "old password is rejected"

      basic_authorize "heli", "newpw"
      get "/v3/whoami"
      assert_200
    end

    it "does not break active ldap" do
      maintenance_group = Group.find(:first,
                                     :attribute => 'cn',
                                     :value     => 'maintenance')
      user = PuavoRest::User.new(
        :email      => 'mark@example.com',
        :first_name => 'Mark',
        :last_name  => 'Hamill',
        :locale     => 'en_US.UTF-8',
        :password   => 'secret',
        :roles      => [ 'student' ],
        :school_dns => [ @school.dn.to_s ],
        :username   => 'mark',
      )
      user.save!

      # XXX weird that these must be here
      user.administrative_groups = [ maintenance_group.id ]
      user.teaching_group = @group
    end

    it "can add and remove groups" do
      @user.teaching_group = @teaching_group
      @user.year_class = @year_class

      assert @teaching_group.member_dns.include?(@user.dn), "User is not group member"
      assert_equal @user.teaching_group.name, "5A"

      assert @year_class.member_dns.include?(@user.dn), "User is not group member"
      assert_equal @user.year_class.name, "5"

      @user.teaching_group = nil
      @teaching_group = PuavoRest::Group.by_id(@teaching_group.id) # FIXME? why should be reload from ldap?
      assert !@teaching_group.member_dns.include?(@user.dn), "User is group member"
      assert_nil @user.teaching_group

    end

    it "cannot have duplicate external IDs" do
      @donald = PuavoRest::User.new(
        :first_name => "Donald",
        :last_name => "Duck",
        :username => "donald.duck",
        :school_dns => [@school.dn.to_s],
        :roles => ["student"],
        :external_id => "donald")

      assert @donald.save!

      # This will fail because we're reusing Donald's external ID
      @daisy = PuavoRest::User.new(
        :first_name => "Daisy",
        :last_name => "Duck",
        :username => "daisy.duck",
        :school_dns => [@school.dn.to_s],
        :roles => ["student"],
        :external_id => "donald"
      )

      exception = assert_raises ValidationError do
        assert @daisy.save!
      end

      # Who created this error message? Seriously.
      assert_equal("Creating\n  Invalid attributes for PuavoRest::User " +
                   ":\n    * external_id: external_id=donald is not unique\n\n",
                   exception.message)

      # Change the external ID and try again. Have to create a new object
      # because it's filled with LDAP junk during the insertion attempt.
      @daisy = PuavoRest::User.new(
        :first_name => "Daisy",
        :last_name => "Duck",
        :username => "daisy.duck",
        :school_dns => [@school.dn.to_s],
        :roles => ["student"],
        :external_id => "daisy"
      )

      assert @daisy.save!
    end

    it "duplicate attributes do not cause problems" do
      user = PuavoRest::User.new
      user.first_name = 'Duplicate'
      user.last_name = 'Attribute'
      user.username = 'dulpicate.attribute'   # oops, typo'd the name
      user.username = 'duplicate.attribute'   # there, much better
      user.roles = ['testuser']
      user.school_dns = [@school.dn.to_s]
      assert user.save!

      user = PuavoRest::User.by_dn!(user.dn)
      assert_equal user.username, 'duplicate.attribute'
    end
  end
end

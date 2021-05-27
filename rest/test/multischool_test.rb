require_relative "./helper"

describe PuavoRest::Users do

  IMG_FIXTURE = File.join(File.dirname(__FILE__), "fixtures", "profile.jpg")

  before(:each) do
    Puavo::Test.clean_up_ldap
    setup_ldap_admin_connection()

    @school1 = School.create(
      :cn => "school1",
      :displayName => "School 1",
    )

    @school2 = School.create(
      :cn => "school2",
      :displayName => "School 2",
    )

    @school3 = School.create(
      :cn => "school3",
      :displayName => "School 3",
    )

    @user1 = PuavoRest::User.new(
      :first_name        => 'Bob',
      :last_name         => 'Brown',
      :username          => 'bob',
      :roles             => ['testuser'],
      :school_dns        => [@school1.dn.to_s],
      :primary_school_dn => @school1.dn.to_s,
      :password          => 'password',
    )

    @user1.save!

    @user2 = PuavoRest::User.new(
      :first_name        => 'Alice',
      :last_name         => 'Brown',
      :username          => 'alice',
      :roles             => ['testuser'],
      :school_dns        => [@school1.dn.to_s, @school2.dn.to_s],
      :primary_school_dn => @school1.dn.to_s,
      :password          => 'password',
    )

    @user2.save!

    @user3 = PuavoRest::User.new(
      :first_name          => 'Admin',
      :last_name           => 'One',
      :username            => 'admin1',
      :roles               => ['admin'],
      :school_dns          => [@school1.dn.to_s, @school2.dn.to_s],
      :admin_of_school_dns => [@school2.dn.to_s],
      :primary_school_dn   => @school1.dn.to_s,
      :password            => 'password',
    )

    @user3.save!

    @user4 = PuavoRest::User.new(
      :first_name          => 'Admin',
      :last_name           => 'Two',
      :username            => 'admin2',
      :roles               => ['admin'],
      :school_dns          => [@school1.dn.to_s, @school2.dn.to_s],
      :admin_of_school_dns => [@school1.dn.to_s, @school2.dn.to_s],
      :primary_school_dn   => @school1.dn.to_s,
      :password            => 'password',
    )

    @user4.save!

    @user5 = PuavoRest::User.new(
      :first_name          => 'Admin',
      :last_name           => 'Three',
      :username            => 'admin3',
      :roles               => ['admin'],
      :school_dns          => [@school1.dn.to_s],
      :admin_of_school_dns => [@school3.dn.to_s],   # this user is not in this school, but has admin rights to it
      :primary_school_dn   => @school1.dn.to_s,
      :password            => 'password',
    )

    @user5.save!

    @school1.puavoSchoolAdmin = [@user4.dn.to_s]
    @school1.save!

    @school2.puavoSchoolAdmin = [@user3.dn.to_s, @user4.dn.to_s]
    @school2.save!

    @school3.puavoSchoolAdmin = [@user5.dn.to_s]
    @school3.save!
  end

  describe "Adding and removing multiple schools" do
    it "add another school" do
      user = PuavoRest::User.by_attr(:username, 'bob')

      # Add another school
      user.school_dns = [@school1.dn.to_s, @school2.dn.to_s]
      assert user.save!

      # Verify
      user = PuavoRest::User.by_attr(:username, 'bob')
      assert_equal user.school_dns, [@school1.dn.to_s, @school2.dn.to_s]
      assert_equal user.school.dn, @school1.dn.to_s
      assert_equal user.schools.count, 2
      assert_equal user.schools[0].dn, @school1.dn.to_s
      assert_equal user.schools[1].dn, @school2.dn.to_s
      assert_equal user.primary_school_dn, @school1.dn.to_s

      basic_authorize 'bob', 'password'
      get '/v3/users/bob'
      assert_200
      data = JSON.parse(last_response.body)
      assert_equal data['schools'].count, 2
      assert_equal data['school_dn'], @school1.dn.to_s
      assert_equal data['school_dns'].sort, [@school1.dn.to_s, @school2.dn.to_s].sort
      assert_equal data['primary_school_dn'], @school1.dn.to_s
    end

    it "remove from multiple schools" do
      user = PuavoRest::User.by_attr(:username, 'alice')

      # Remove from the first school
      user.school_dns = [@school2.dn.to_s]
      user.primary_school_dn = @school2.dn.to_s
      assert user.save!

      # And verify
      user = PuavoRest::User.by_attr(:username, 'alice')
      assert_equal user.school_dns, [@school2.dn.to_s]
      assert_equal user.school.dn, @school2.dn.to_s
      assert_equal user.schools.count, 1
      assert_equal user.schools[0].dn, @school2.dn.to_s
      assert_equal user.primary_school_dn, @school2.dn.to_s

      basic_authorize 'alice', 'password'
      get '/v3/users/alice'
      assert_200
      data = JSON.parse(last_response.body)
      assert_equal data['schools'].count, 1
      assert_equal data['school_dn'], @school2.dn.to_s
      assert_equal data['school_dns'], [@school2.dn.to_s]
      assert_equal data['primary_school_dn'], @school2.dn.to_s
    end

    it "move to another school 1" do
      user = PuavoRest::User.by_attr(:username, 'bob')

      # Change the school
      user.school_dns = [@school2.dn.to_s]
      user.primary_school_dn = @school2.dn.to_s
      assert user.save!

      # Verify
      user = PuavoRest::User.by_attr(:username, 'bob')
      assert_equal user.school_dns, [@school2.dn.to_s]
      assert_equal user.school.dn, @school2.dn.to_s
      assert_equal user.schools.count, 1
      assert_equal user.schools[0].dn, @school2.dn.to_s
      assert_equal user.primary_school_dn, @school2.dn.to_s

      basic_authorize 'bob', 'password'
      get '/v3/users/bob'
      assert_200
      data = JSON.parse(last_response.body)
      assert_equal data['schools'].count, 1
      assert_equal data['school_dn'], @school2.dn.to_s
      assert_equal data['school_dns'], [@school2.dn.to_s]
      assert_equal data['primary_school_dn'], @school2.dn.to_s
    end

    #~ # CAUTION: These two tests assume the underlying arrays remain in order. LDAP does
    #~ # not guarantee this, but it kind-of works in openldap.

    it "move to another school 2A (faulty)" do
      user = PuavoRest::User.by_attr(:username, 'alice')

      # Swap the schools. We don't change primary_school_dn, so the primary school does not
      # actually change and user.school still points to the "old" primary school.
      user.school_dns = [@school2.dn.to_s, @school1.dn.to_s]
      assert user.save!

      # Verify
      user = PuavoRest::User.by_attr(:username, 'alice')
      assert_equal user.school_dns, [@school2.dn.to_s, @school1.dn.to_s]
      assert_equal user.school.dn, @school1.dn.to_s
      assert_equal user.schools.count, 2
      assert_equal user.schools[0].dn, @school2.dn.to_s
      assert_equal user.schools[1].dn, @school1.dn.to_s
      assert_equal user.primary_school_dn, @school1.dn.to_s

      basic_authorize 'alice', 'password'
      get '/v3/users/alice'
      assert_200
      data = JSON.parse(last_response.body)
      assert_equal data['schools'].count, 2
      assert_equal data['school_dn'], @school1.dn.to_s
      assert_equal data['school_dns'], [@school2.dn.to_s, @school1.dn.to_s]
      assert_equal data['primary_school_dn'], @school1.dn.to_s
    end

    it "move to another school 2B (correct)" do
      user = PuavoRest::User.by_attr(:username, 'alice')

      # Swap the schools. Now we set the correct DN too, so the primary school actually changes.
      user.school_dns = [@school2.dn.to_s, @school1.dn.to_s]
      user.primary_school_dn = @school2.dn.to_s
      assert user.save!

      # Verify
      user = PuavoRest::User.by_attr(:username, 'alice')
      assert_equal user.school_dns, [@school2.dn.to_s, @school1.dn.to_s]
      assert_equal user.school.dn, @school2.dn.to_s
      assert_equal user.schools.count, 2
      assert_equal user.schools[0].dn, @school2.dn.to_s
      assert_equal user.schools[1].dn, @school1.dn.to_s
      assert_equal user.primary_school_dn, @school2.dn.to_s

      basic_authorize 'alice', 'password'
      get '/v3/users/alice'
      assert_200
      data = JSON.parse(last_response.body)
      assert_equal data['schools'].count, 2
      assert_equal data['school_dn'], @school2.dn.to_s
      assert_equal data['school_dns'], [@school2.dn.to_s, @school1.dn.to_s]
      assert_equal data['primary_school_dn'], @school2.dn.to_s
    end

    it "move to another school 3" do
      user = PuavoRest::User.by_attr(:username, 'alice')

      # Add a completely new school into the mix
      user.school_dns = [@school3.dn.to_s, @school1.dn.to_s, @school2.dn.to_s]
      user.primary_school_dn = @school3.dn.to_s
      assert user.save!

      # Verify
      user = PuavoRest::User.by_attr(:username, 'alice')
      assert_equal user.school_dns, [@school3.dn.to_s, @school1.dn.to_s, @school2.dn.to_s]
      assert_equal user.school.dn, @school3.dn.to_s
      assert_equal user.primary_school_dn, @school3.dn.to_s
      assert_equal user.schools.count, 3
      assert_equal user.schools[0].dn, @school3.dn.to_s
      assert_equal user.schools[1].dn, @school1.dn.to_s
      assert_equal user.schools[2].dn, @school2.dn.to_s

      basic_authorize 'alice', 'password'
      get '/v3/users/alice'
      assert_200
      data = JSON.parse(last_response.body)
      assert_equal data['schools'].count, 3
      assert_equal data['schools'][0]['dn'], @school3.dn.to_s
      assert_equal data['schools'][1]['dn'], @school1.dn.to_s
      assert_equal data['schools'][2]['dn'], @school2.dn.to_s
      assert_equal data['school_dn'], @school3.dn.to_s
      assert_equal data['school_dns'], [@school3.dn.to_s, @school1.dn.to_s, @school2.dn.to_s]
      assert_equal data['primary_school_dn'], @school3.dn.to_s
    end
  end

  describe "Multi-school admin tests" do
    it "admin in one school" do
      # Check
      school = PuavoRest::School.by_attr(:abbreviation, 'school1')
      assert_equal school.school_admin_dns, [@user4.dn.to_s]
      school = PuavoRest::School.by_attr(:abbreviation, 'school2')
      assert_equal school.school_admin_dns, [@user3.dn.to_s, @user4.dn.to_s]
      user = PuavoRest::User.by_attr(:username, 'admin1')
      assert_equal user.admin_of_school_dns, [school.dn.to_s]

      # Remove Admin One from school 2
      user.school_dns = [@school1.dn.to_s]
      assert user.save!

      # Verify
      school = PuavoRest::School.by_attr(:abbreviation, 'school2')
      assert_equal school.school_admin_dns, [@user4.dn.to_s]
      user = PuavoRest::User.by_attr(:username, 'admin1')
      assert_equal user.admin_of_school_dns, []

      # admin2 should not have been clobbered
      school = PuavoRest::School.by_attr(:abbreviation, 'school1')
      assert_equal school.school_admin_dns, [@user4.dn.to_s]
      school = PuavoRest::School.by_attr(:abbreviation, 'school2')
      assert_equal school.school_admin_dns, [@user4.dn.to_s]
      user = PuavoRest::User.by_attr(:username, 'admin2')
      assert_equal user.admin_of_school_dns, [@school1.dn.to_s, @school2.dn.to_s]
    end

    it "admin in multiple schools" do
      # Check
      school = PuavoRest::School.by_attr(:abbreviation, 'school1')
      assert_equal school.school_admin_dns, [@user4.dn.to_s]
      school = PuavoRest::School.by_attr(:abbreviation, 'school2')
      assert_equal school.school_admin_dns, [@user3.dn.to_s, @user4.dn.to_s]
      user = PuavoRest::User.by_attr(:username, 'admin2')
      assert_equal user.admin_of_school_dns, [@school1.dn.to_s, @school2.dn.to_s]

      # Remove Admin Two from school 1
      user.school_dns = [@school2.dn.to_s]
      user.primary_school_dn = @school2.dn.to_s
      assert user.save!

      # Verify
      school = PuavoRest::School.by_attr(:abbreviation, 'school1')
      assert_equal school.school_admin_dns, []
      school = PuavoRest::School.by_attr(:abbreviation, 'school2')
      assert_equal school.school_admin_dns, [@user3.dn.to_s, @user4.dn.to_s]
      user = PuavoRest::User.by_attr(:username, 'admin2')
      assert_equal user.admin_of_school_dns, [@school2.dn.to_s]

      # admin1 should not have been clobbered
      user = PuavoRest::User.by_attr(:username, 'admin1')
      assert_equal user.admin_of_school_dns, [@school2.dn.to_s]
    end
  end

  describe "Multi-school user removal tests" do
    it "deleting a multi-school user removes them from all schools" do
      school = PuavoRest::School.by_attr(:abbreviation, "school1")
      assert_equal school.member_usernames.sort, ["admin1", "admin2", "admin3", "alice", "bob"]

      PuavoRest::User.by_attr(:username, "alice").destroy!

      school = PuavoRest::School.by_attr(:abbreviation, "school1")
      assert_equal school.member_usernames.sort, ["admin1", "admin2", "admin3", "bob"]
      school = PuavoRest::School.by_attr(:abbreviation, "school2")
      assert_equal school.member_usernames.sort, ["admin1", "admin2"]
    end

    it "deleting a multi-school admin user cleans up school admin arrays" do
      school = PuavoRest::School.by_attr(:abbreviation, "school1")
      assert_equal school.member_usernames.sort, ["admin1", "admin2", "admin3", "alice", "bob"]
      assert_equal school.member_dns.sort, [@user1.dn.to_s, @user2.dn.to_s, @user3.dn.to_s, @user4.dn.to_s, @user5.dn.to_s]
      assert_equal school.school_admin_dns.sort, [@user4.dn.to_s]

      school = PuavoRest::School.by_attr(:abbreviation, "school2")
      assert_equal school.member_usernames.sort, ["admin1", "admin2", "alice"]
      assert_equal school.school_admin_dns.sort, [@user3.dn.to_s, @user4.dn.to_s]

      # Calling @user4.destroy! here is a fatal mistake. The @user4 object is cached and it
      # does NOT contain updated admin DN lists, so those associations would be left stale!
      # The same warning applies to all user deletion tests here.
      PuavoRest::User.by_attr(:username, "admin2").destroy!

      school = PuavoRest::School.by_attr(:abbreviation, "school1")
      assert_equal school.member_usernames.sort, ["admin1", "admin3", "alice", "bob"]
      assert_equal school.member_dns.sort, [@user1.dn.to_s, @user2.dn.to_s, @user3.dn.to_s, @user5.dn.to_s]
      assert_equal school.school_admin_dns.sort, []

      school = PuavoRest::School.by_attr(:abbreviation, "school2")
      assert_equal school.member_usernames.sort, ["admin1", "alice"]
      assert_equal school.member_dns.sort, [@user2.dn.to_s, @user3.dn.to_s]
      assert_equal school.school_admin_dns.sort, [@user3.dn.to_s]
    end

    it "more school admin array cleanups" do
      # For some reason, we allow an admin to administrate a school they aren't a member of.
      # These associations must also be removed upon deletion.
      school = PuavoRest::School.by_attr(:abbreviation, "school3")
      assert_equal school.member_usernames.sort, []
      assert_equal school.member_dns.sort, []
      assert_equal school.school_admin_dns.sort, [@user5.dn.to_s]

      PuavoRest::User.by_attr(:username, "admin3").destroy!

      school = PuavoRest::School.by_attr(:abbreviation, "school3")
      assert_equal school.member_usernames.sort, []
      assert_equal school.member_dns.sort, []
      assert_equal school.school_admin_dns.sort, []
    end
  end

  describe "User creation and updating tests" do
    it "creating a user with only one school fixes the missing primary school DN automatically" do
      u = PuavoRest::User.new(
        :first_name => 'Missing',
        :last_name  => 'School',
        :username   => 'missing1',
        :roles      => ['testuser'],
        :school_dns => [@school1.dn.to_s],
      )

      assert u.save!

      u = PuavoRest::User.by_attr(:username, 'missing1')
      assert_equal u.primary_school_dn, @school1.dn.to_s
    end

    it "multiple schools for a new user will fail" do
      u = PuavoRest::User.new(
        :first_name => 'Missing',
        :last_name  => 'School',
        :username   => 'missing2',
        :roles      => ['testuser'],
        :school_dns => [@school1.dn.to_s, @school2.dn.to_s],
      )

      exception = assert_raises InternalError do
        assert u.save!
      end

      assert_equal("user missing2 has multiple schools but no primary school DN",
                   exception.message)
    end

    it "intentionally incorrect primary school DN" do
      u = PuavoRest::User.new(
        :first_name        => 'Missing',
        :last_name         => 'School',
        :username          => 'missing3',
        :roles             => ['testuser'],
        :school_dns        => [@school1.dn.to_s],
        :primary_school_dn => @school1.dn.to_s + 'x',
      )

      assert_raises ValidationError do
        assert u.save!
      end
    end

    it "intentionally incorrect primary school DN" do
      u = PuavoRest::User.new(
        :first_name        => 'Missing',
        :last_name         => 'School',
        :username          => 'missing4',
        :roles             => ['testuser'],
        :school_dns        => [@school1.dn.to_s, @school2.dn.to_s],
        :primary_school_dn => @school3.dn.to_s,   # a valid DN but wrong school
      )

      exception = assert_raises ValidationError do
        assert u.save!
      end

      assert exception.to_s.include?("primary_school_dn: primary_school_dn points to a school " +
                                     "that isn't in the school_dns array")
    end
  end
end

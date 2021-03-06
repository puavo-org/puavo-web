require_relative "./helper"

describe LdapModel do

  describe "user school relations" do

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

      @school_other = School.create(
        :cn => "otherschool",
        :displayName => "Other school",
        :puavoSchoolHomePageURL => "otherschool.example"
      )

      @group_other = PuavoRest::Group.new(
        :abbreviation => 'othergroup',
        :name         => 'Group Other',
        :school_dn    => @school.dn.to_s,
        :type         => 'teaching group')
      @group_other.save!

      user = PuavoRest::User.new(
        :email      => 'heli.kopteri@example.com',
        :first_name => 'Heli',
        :last_name  => 'Kopteri',
        :password   => 'userpassswordislong',
        :roles      => [ 'staff' ],
        :school_dns => [ @school.dn.to_s ],
        :username   => 'heli',
      )
      user.save!
      @user_dn = user.dn.to_s
    end

    it "are set on creation" do
      school = PuavoRest::School.by_dn(@school.dn)
      assert school.member_usernames.include?("heli"), "has username rel"
      assert school.member_dns.include?(@user_dn), "has dn rel"
    end

    it "are added on update" do
      user = PuavoRest::User.by_dn!(@user_dn)
      user.school_dns.push(@school_other.dn.to_s)
      user.save!

      other_school = PuavoRest::School.by_dn(@school_other.dn)
      assert other_school.member_usernames.include?("heli"), "has username rel"
      assert other_school.member_dns.include?(@user_dn), "has dn rel"
    end

    it "are removed after removing school from user" do
      user = PuavoRest::User.by_dn!(@user_dn)
      user.school_dns = [@school_other.dn.to_s]
      user.primary_school_dn = [@school_other.dn.to_s]
      user.save!

      school = PuavoRest::School.by_dn(@school.dn.to_s)
      assert !school.member_usernames.include?("heli"), "username rel was removed"
      assert !school.member_dns.include?(@user_dn), "dn rel was removed"

      other_school = PuavoRest::School.by_dn(@school_other.dn)
      assert other_school.member_usernames.include?("heli"), "has username rel"
      assert other_school.member_dns.include?(@user_dn), "has dn rel"
    end

    it "are fixed on save if broken" do
      user = PuavoRest::User.by_dn!(@user_dn)

      # Break relation
      school = PuavoRest::School.by_dn(@school.dn)
      school.member_usernames = []
      school.member_dns = []
      school.save!

      assert school.refresh.member_dns.empty?
      assert school.refresh.member_usernames.empty?

      # Create invalid relation
      other_school = PuavoRest::School.by_dn(@school_other.dn)
      other_school.member_usernames = ["heli"]
      other_school.member_dns = [user.dn]
      other_school.save!

      assert other_school.refresh.member_dns.include?(user.dn)
      assert other_school.refresh.member_usernames.include?("heli")

      # Fix everything!
      user.save!

      assert school.refresh.member_dns.include?(user.dn), "school should have dn rel again"
      assert school.refresh.member_usernames.include?("heli"), "school should have username rel again"

      assert other_school.refresh.member_dns.empty?, "other school should not have the invalid dn rel"
      assert other_school.refresh.member_usernames.empty?, "other school should not have the invalid username rel"

    end

  end
end

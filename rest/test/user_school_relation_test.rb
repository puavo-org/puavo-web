require_relative "./helper"
require_relative "../lib/ldapmodel"

describe LdapModel do

  describe "user school relations" do

    before(:each) do
      Puavo::Test.clean_up_ldap
      @school = School.create(
        :cn => "gryffindor",
        :displayName => "Gryffindor",
        :puavoSchoolHomePageURL => "schoolhomepage.example"
      )

      @group = Group.new
      @group.cn = "group1"
      @group.displayName = "Group 1"
      @group.puavoSchool = @school.dn
      @group.save!

      @role = Role.new
      @role.displayName = "Some role"
      @role.puavoSchool = @school.dn
      @role.groups << @group
      @role.save!

      @school_other = School.create(
        :cn => "otherschool",
        :displayName => "Other school",
        :puavoSchoolHomePageURL => "otherschool.example"
      )

      @group_other = Group.new
      @group_other.cn = "othergroup"
      @group_other.displayName = "Group Other"
      @group_other.puavoSchool = @school_other.dn
      @group_other.save!

      @role_other = Role.new
      @role_other.displayName = "Other Role"
      @role_other.puavoSchool = @school_other.dn
      @role_other.groups << @group_other
      @role_other.save!

      LdapModel.setup(
        :organisation => PuavoRest::Organisation.default_organisation_domain!,
        :rest_root => "http://" + CONFIG["default_organisation_domain"],
        :credentials => {
          :dn => PUAVO_ETC.ldap_dn,
          :password => PUAVO_ETC.ldap_password }
      )
      user = PuavoRest::User.new(
        :first_name => "Heli",
        :last_name => "Kopteri",
        :username => "heli",
        :roles => ["staff"],
        :email => "heli.kopteri@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "userpassswordislong"
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

      assert school.refresh.member_dns.include?(user.dn), "school should dn rel again"
      assert school.refresh.member_usernames.include?("heli"), "school should username rel again"

      assert other_school.refresh.member_dns.empty?, "other school should not have the invalid dn rel"
      assert other_school.refresh.member_usernames.empty?, "other school should not have the invalid username rel"

    end

  end
end

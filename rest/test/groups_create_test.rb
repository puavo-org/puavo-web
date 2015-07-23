require_relative "./helper"
require_relative "../lib/ldapmodel"

describe LdapModel do

  describe "group creation" do

    before(:each) do
      Puavo::Test.clean_up_ldap

      LdapModel.setup(
        :organisation => PuavoRest::Organisation.default_organisation_domain!,
        :rest_root => "http://" + CONFIG["default_organisation_domain"],
        :credentials => {
          :dn => PUAVO_ETC.ldap_dn,
          :password => PUAVO_ETC.ldap_password }
      )

      @school = PuavoRest::School.new(
        :name => "Test School 1",
        :abbreviation => "testschool1"
      )
      @school.save!

      @group = PuavoRest::Group.new(
        :name => "Test group 1",
        :abbreviation => "testgroup1",
        :school_dn => @school.dn
      )
      @group.save!

    end

    it "has Fixnum id" do
      assert_equal Fixnum, @group.id.class
    end

  end
end

require_relative "./helper"

describe LdapModel do

  describe "school creation" do

    before(:each) do
      Puavo::Test.clean_up_ldap
      setup_ldap_admin_connection()

      @school = PuavoRest::School.new(
        :name => "Test School 1",
        :abbreviation => "testschool1"
      )

      @school.save!
    end

    it "has String id" do
      assert_equal String, @school.id.class
    end

    it "has dn" do
      assert @school.dn, "model got dn"
    end

    it "has Fixnum gid_number" do
        assert_equal Fixnum, @school.gid_number.class
    end

    it "has name" do
      assert_equal "Test School 1", @school.name
    end

    it "has internal samba attributes" do
      assert_equal ["2"], @school.get_raw(:sambaGroupType)

      samba_sid = @school.get_raw(:sambaSID)
      assert samba_sid
      assert samba_sid.first
      assert_equal "S", samba_sid.first.first

    end

  end
end

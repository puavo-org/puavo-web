require_relative "./helper"

describe LdapModel do

  describe "school creation" do

    before(:each) do
      Puavo::Test.clean_up_ldap
      setup_ldap_admin_connection()

      @school = PuavoRest::School.new(
        :name => "Test School 1",
        :abbreviation => "testschool1",
        :description => 'School description',
        :notes => 'School notes',
      )

      @school.save!
    end

    it "has String id" do
      assert_equal String, @school.id.class
    end

    it "has dn" do
      assert @school.dn, "model got dn"
    end

    it "has Integer gid_number" do
        assert_equal Integer, @school.gid_number.class
    end

    it "has name" do
      assert_equal "Test School 1", @school.name
    end

    it 'has description' do
      assert_equal 'School description', @school.description
    end

    it 'has notes' do
      school = PuavoRest::School.by_dn!(@school.dn)
      assert_equal 'School notes', school.notes
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

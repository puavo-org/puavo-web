
require_relative "./helper"

module School_test
describe PuavoRest::School do


  before(:each) do
    Puavo::Test.clean_up_ldap
    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor",
      :preferredLanguage => "school-lang",
      :puavoSchoolHomePageURL => "gryffindor.example"
    )

    @school.save!

    @school2 = School.create(
      :cn => "school2",
      :displayName => "School 2",
      :puavoSchoolCode => "0123450",
    )

    @school2.save!

    @server = create_server(
      :puavoHostname => "server",
      :macAddress => "bc:5f:f4:56:59:72",
      :puavoDeviceType => "bootserver",
      :puavoSchool => @school.dn
    )
    PuavoRest.test_boot_server_dn = @server.dn.to_s

    setup_ldap_admin_connection()
  end

  it "school codes are what they should be" do
    assert_nil PuavoRest::School.by_dn!(@school.dn).school_code
    assert_equal PuavoRest::School.by_dn!(@school2.dn).school_code, "0123450"
  end

  it "can change te school code for a school that does not have it yet" do
    school = PuavoRest::School.by_dn!(@school.dn)
    school.school_code = "foobar"
    school.save!
    assert_equal PuavoRest::School.by_dn!(@school.dn).school_code, "foobar"
  end

  it "can change te school code for a school that does have it already" do
    school = PuavoRest::School.by_dn!(@school2.dn)
    school.school_code = "bazquux"
    school.save!
    assert_equal PuavoRest::School.by_dn!(@school2.dn).school_code, "bazquux"
  end

  it "can clear the school code" do
    school = PuavoRest::School.by_dn!(@school.dn)
    school.school_code = nil
    school.save!
    school = PuavoRest::School.by_dn!(@school2.dn)
    school.school_code = nil
    school.save!
    assert_nil PuavoRest::School.by_dn!(@school.dn).school_code
    assert_nil PuavoRest::School.by_dn!(@school2.dn).school_code
  end

end
end


require_relative "./helper"

module School_test
describe PuavoRest::School do


  before(:each) do
    Puavo::Test.clean_up_ldap
    PuavoRest::Session.local_store.flushdb
    FileUtils.rm_rf CONFIG["ltsp_server_data_dir"]
    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor",
      :preferredLanguage => "school-lang",
      :puavoSchoolHomePageURL => "gryffindor.example"
    )

    @school.external_feed = "http://example.com/cal.ics"
    @school.save!

    LdapModel.setup(
      :organisation =>
        PuavoRest::Organisation.default_organisation_domain!,
      :rest_root => "http://" + CONFIG["default_organisation_domain"],
                    :credentials => { :dn => PUAVO_ETC.ldap_dn, :password => PUAVO_ETC.ldap_password }
    )

  end

  it "has external_feed" do
    school = PuavoRest::School.by_dn!(@school.dn)
    assert school.external_feed
    assert_equal(
      [
        {
          "type"=>"ical",
         "name"=>"Opinsys",
         "value"=>"http://example.com/cal.ics"
        }
      ],
      school.external_feed
    )
  end



end
end

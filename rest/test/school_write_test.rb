require_relative "./helper"

describe PuavoRest::Devices do

  before(:each) do
    Puavo::Test.clean_up_ldap
    school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor",
      :puavoDeviceImage => "schoolprefimage",
      :puavoPersonalDevice => true,
      :puavoSchoolHomePageURL => "schoolhomepagefordevice.example",
      :puavoAllowGuest => true,
      :puavoAutomaticImageUpdates => true,
      :puavoImageSeriesSourceURL => "https://foobar.puavo.net/schoolpref.json",
      :puavoLocale => "fi_FI.UTF-8",
      :puavoTag => ["schooltag"],
      :puavoMountpoint => [ '{"fs":"nfs3","path":"10.0.0.3/share","mountpoint":"/home/school/share","options":"-o r"}',
                            '{"fs":"nfs4","path":"10.5.5.3/share","mountpoint":"/home/school/public","options":"-o r"}' ]
    )

    @school_dn = school.dn

    PuavoRest::Organisation.refresh
    setup_ldap_admin_connection()
  end

  it "can write name attribte" do
    school = PuavoRest::School.by_dn!(@school_dn)
    assert_equal "Gryffindor", school.name
    school.name = "New name"
    assert_equal "New name", school.name

    school.save!
    school = PuavoRest::School.by_dn!(school.dn)
    assert_equal "New name", school.name
  end

  it "can write mountpoints attribute with hash" do
    school = PuavoRest::School.by_dn!(@school_dn)
    assert_equal "nfs3", school.mountpoints[0]["fs"]

    mps = JSON.parse(school.mountpoints.to_json) # dup deep
    mps[0]["fs"] = "sshfs"
    school.mountpoints = mps
    assert_equal "sshfs", school.mountpoints[0]["fs"]
    school.save!

    school = PuavoRest::School.by_dn!(@school_dn)
    assert_equal "sshfs", school.mountpoints[0]["fs"]
  end

end

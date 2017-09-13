require_relative "./helper"

describe PuavoRest::ExternalLogin do

  before(:each) do
    Puavo::Test.clean_up_ldap

    # XXX could the ext_school -stuff be created to a different organisation
    # XXX altogether?
    # XXX how to set up puavo-rest.yml for this only?
    # XXX (we should manipulate CONFIG somehow)

    @ext_school = School.create(
      :cn          => 'uagadou',
      :displayName => 'Uagadou',
    )

    @ext_group = Group.new
    @ext_group.cn                = 'extgroup1'
    @ext_group.displayName       = 'External Group 1'
    @ext_group.puavoSchool       = @ext_school.dn
    @ext_group.puavoEduGroupType = 'teaching group'
    @ext_group.save!

    @ext_role = Role.new
    @ext_role.displayName = 'Some role'
    @ext_role.puavoSchool = @ext_school.dn
    @ext_role.groups << @ext_group
    @ext_role.save!

    @ext_user1 = User.new(
      :givenName => 'Babajide',
      :sn  => 'Akingbade',
      :uid => 'babajide.akingbade',
      :puavoEduPersonAffiliation => 'student',
      :puavoLocale => 'en_US.UTF-8',
      :mail => ['babajide.akingbade@example.com'],
      :role_ids => [ @ext_role.puavoId ],
      :puavoSshPublicKey => 'asdfsdfdfsdfwersSSH_PUBLIC_KEYfdsasdfasdfadf',
    )

    @our_school = School.create(
      :cn          => 'gryffindor',
      :displayName => 'Gryffindor',
    )
  end

  it "has file metadata in index" do
    get "/v3/external_files"
    assert_200
    data = JSON.parse last_response.body

    assert_equal "test.txt", data[0]["name"]
    assert_equal "f48dd853820860816c75d54d0f584dc863327a7c", data[0]["data_hash"]

    assert_equal "another.txt", data[1]["name"]
    assert_equal "7bd8e7cb8e1e8b7b2e94b472422512935c9d4519", data[1]["data_hash"]
  end

  it "has file contents" do
    get "/v3/external_files/test.txt"
    assert_200
    assert_equal "test data", last_response.body
  end

  it "has file metadata" do
    get "/v3/external_files/test.txt/metadata"
    assert_200
    data = JSON.parse last_response.body

    assert_equal "test.txt", data["name"]
    assert_equal "f48dd853820860816c75d54d0f584dc863327a7c", data["data_hash"]
  end

  it "has file metadata in index by device" do
    get "/v3/devices/athin01/external_files"
    assert_200
    data = JSON.parse last_response.body

    assert_equal "test.txt", data[0]["name"]
    assert_equal "f48dd853820860816c75d54d0f584dc863327a7c", data[0]["data_hash"]

    assert_equal "another.txt", data[1]["name"]
    assert_equal "7bd8e7cb8e1e8b7b2e94b472422512935c9d4519", data[1]["data_hash"]

    assert_equal "printer.ppd", data[2]["name"]
    assert_equal "f6faa9d255137ce1482dc9a958f7299c234ef4f9", data[2]["data_hash"]

  end

  it "has no file metadata of printer_ppd in index by device" do
    get "/v3/devices/athin02/external_files"
    assert_200
    data = JSON.parse last_response.body

    assert_equal "test.txt", data[0]["name"]
    assert_equal "f48dd853820860816c75d54d0f584dc863327a7c", data[0]["data_hash"]

    assert_equal "another.txt", data[1]["name"]
    assert_equal "7bd8e7cb8e1e8b7b2e94b472422512935c9d4519", data[1]["data_hash"]
  end

  it "has printer.ppd file contents by hostname" do
    get "/v3/devices/athin01/external_files/printer.ppd"
    assert_200
    assert_equal "PPD-data", last_response.body
  end

  it "has file contents by hostname" do
    get "/v3/devices/athin01/external_files/test.txt"
    assert_200
    assert_equal "test data", last_response.body
  end

end

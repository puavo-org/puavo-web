
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
      :puavoNotes => 'Muistiinpanoja',
      :puavoConf => {
        'key' => 'value'
      }.to_json
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

  it 'can change and clear the notes' do
    school = PuavoRest::School.by_dn!(@school2.dn)
    assert_equal 'Muistiinpanoja', school.notes
    school.notes = 'Notes'
    school.save!

    school = PuavoRest::School.by_dn!(@school2.dn)
    assert_equal 'Notes', school.notes
    school.notes = nil
    school.save!

    school = PuavoRest::School.by_dn!(@school2.dn)
    assert_nil school.notes
  end

  describe 'puavoconf endpoint tests' do
    it 'get all puavoconf values' do
      basic_authorize 'uid=admin,o=puavo', 'password'
      get "/v3/schools/#{@school2.id}/puavoconf"
      assert_equal 200, last_response.status
      conf = JSON.parse(last_response.body)
      assert conf.include?('key') && conf['key'] == 'value'
    end

    it 'create, update and delete single puavoconf values' do
      # Create
      basic_authorize 'uid=admin,o=puavo', 'password'
      header 'Content-Type', 'text/plain'
      put "/v3/schools/#{@school2.id}/puavoconf/some.random.setting", 'some random value'
      assert_equal 201, last_response.status

      # Check
      basic_authorize 'uid=admin,o=puavo', 'password'
      get "/v3/schools/#{@school2.id}/puavoconf"
      conf = JSON.parse(last_response.body)
      assert conf.include?('key') && conf['key'] == 'value'
      assert conf.include?('some.random.setting') && conf['some.random.setting'] == 'some random value'

      # Edit
      basic_authorize 'uid=admin,o=puavo', 'password'
      header 'Content-Type', 'text/plain'
      put "/v3/schools/#{@school2.id}/puavoconf/some.random.setting", 'another value'
      assert_equal 200, last_response.status

      # Check again
      basic_authorize 'uid=admin,o=puavo', 'password'
      get "/v3/schools/#{@school2.id}/puavoconf"
      conf = JSON.parse(last_response.body)
      assert conf.include?('key') && conf['key'] == 'value'
      assert conf.include?('some.random.setting') && conf['some.random.setting'] == 'another value'

      # Delete
      basic_authorize 'uid=admin,o=puavo', 'password'
      header 'Content-Type', 'text/plain'
      delete "/v3/schools/#{@school2.id}/puavoconf/key"
      assert_equal 200, last_response.status

      # Check again
      basic_authorize 'uid=admin,o=puavo', 'password'
      get "/v3/schools/#{@school2.id}/puavoconf"
      conf = JSON.parse(last_response.body)
      assert !conf.include?('key')
      assert conf.include?('some.random.setting') && conf['some.random.setting'] == 'another value'
    end

    it 'trying to delete a non-existent puavoconf value must fail' do
      basic_authorize 'uid=admin,o=puavo', 'password'
      header 'Content-Type', 'text/plain'
      delete "/v3/schools/#{@school2.id}/puavoconf/foobar"
      assert_equal 404, last_response.status
    end

    it 'school puavoconf patching' do
      patch = [
        { 'op' => 'copy', 'from' => '/key', 'path' => '/avain' },
        { 'op' => 'remove', 'path' => '/key' },
      ].to_json

      basic_authorize 'uid=admin,o=puavo', 'password'
      header 'Content-Type', 'application/json-patch+json'
      patch "/v3/schools/#{@school2.id}/puavoconf", patch.to_s
      assert_equal 200, last_response.status

      basic_authorize 'uid=admin,o=puavo', 'password'
      get "/v3/schools/#{@school2.id}/puavoconf"
      conf = JSON.parse(last_response.body)
      assert !conf.include?('key')
      assert conf.include?('avain') && conf['avain'] == 'value'
    end
  end
end
end

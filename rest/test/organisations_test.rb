require_relative "./helper"

describe PuavoRest::Organisations do

  before(:each) do
    Puavo::Test.clean_up_ldap
    setup_ldap_admin_connection()

    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor"
    )

    maintenance_group = Group.find(:first,
                                   :attribute => 'cn',
                                   :value     => 'maintenance')
    @user = PuavoRest::User.new(
      :email                 => 'bob@example.com',
      :first_name            => 'Bob',
      :last_name             => 'Brown',
      :password              => 'secret',
      :preferred_language    => 'en',
      :roles                 => [ 'student' ],
      :school_dns            => [ @school.dn.to_s ],
      :username              => 'bob',
    )
    @user.save!

    # XXX weird that this must be here
    @user.administrative_groups = [ maintenance_group.id ]

    @server1 = Server.new
    @server1.attributes = {
      :puavoHostname => "server1",
      :macAddress => "bc:5f:f4:56:59:71",
      :puavoSchool => @school.dn,
      :puavoTag => ["servertag"],
      :puavoDeviceType => "bootserver",
      :userPassword => "secret"
    }
    @server1.save!

  end

  it "can be fetched by bootserver" do
    basic_authorize @server1.dn, "secret"
    get "/v3/current_organisation"
    assert_200
    data = JSON.parse(last_response.body)
    assert_equal "example.puavo.net", data["domain"]
    assert_equal "cucumber", data["owners"][0]["username"]
  end

  it "can be fetched current organisation" do
    basic_authorize "cucumber", "cucumber"
    get "/v3/current_organisation"
    assert_200
    data = JSON.parse(last_response.body)
    assert_equal "example.puavo.net", data["domain"]
    assert_equal "cucumber", data["owners"][0]["username"]
  end

  describe 'puavoconf endpoint tests' do
    it 'get all puavoconf values' do
      basic_authorize 'uid=admin,o=puavo', 'password'
      get '/v3/organisations/example.puavo.net/puavoconf'
      assert_equal 200, last_response.status
    end

    it 'create, update and delete single puavoconf values' do
      # Create
      basic_authorize 'uid=admin,o=puavo', 'password'
      header 'Content-Type', 'text/plain'
      put '/v3/organisations/example.puavo.net/puavoconf/puavo.xyz', 'text'
      assert [200, 201].include?(last_response.status)    # organistion-level settings don't go away between tests

      # Check
      basic_authorize 'uid=admin,o=puavo', 'password'
      get '/v3/organisations/example.puavo.net/puavoconf'
      conf = JSON.parse(last_response.body)
      assert conf.include?('puavo.xyz') && conf['puavo.xyz'] == 'text'

      # Edit
      basic_authorize 'uid=admin,o=puavo', 'password'
      header 'Content-Type', 'text/plain'
      put '/v3/organisations/example.puavo.net/puavoconf/puavo.xyz', 'more text'
      assert_equal 200, last_response.status

      # Check again
      basic_authorize 'uid=admin,o=puavo', 'password'
      get '/v3/organisations/example.puavo.net/puavoconf'
      conf = JSON.parse(last_response.body)
      assert conf.include?('puavo.xyz') && conf['puavo.xyz'] == 'more text'

      # Delete
      basic_authorize 'uid=admin,o=puavo', 'password'
      header 'Content-Type', 'text/plain'
      delete '/v3/organisations/example.puavo.net/puavoconf/puavo.xyz'
      assert_equal 200, last_response.status

      basic_authorize 'uid=admin,o=puavo', 'password'
      get '/v3/organisations/example.puavo.net/puavoconf'
      conf = JSON.parse(last_response.body)
      assert !conf.include?('some.random.setting')
    end
  end
end

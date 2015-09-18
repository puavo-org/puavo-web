require_relative "./helper"

describe PuavoRest::Organisations do

  before(:each) do
    Puavo::Test.clean_up_ldap
    FileUtils.rm_rf CONFIG["ltsp_server_data_dir"]
    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor"
    )

    @user = User.new(
      :givenName => "Bob",
      :sn  => "Brown",
      :uid => "bob",
      :puavoEduPersonAffiliation => "student",
      :preferredLanguage => "en",
      :mail => "bob@example.com"
    )
    @user.set_password "secret"
    @user.puavoSchool = @school.dn
    @user.role_ids = [
      Role.find(:first, :attribute => "displayName", :value => "Maintenance").puavoId
    ]
    @user.save!

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

  it "can be fetched by admin" do
    basic_authorize "cucumber", "cucumber"
    get "/v3/organisations"
    assert_200
    data = JSON.parse(last_response.body)

    assert(
      !data.select{ |o| o["domain"] == "example.opinsys.net" }.empty?,
      "Has example.opinsys.net"
    )
  end

  it "can be fetched by bootserver" do
    basic_authorize @server1.dn, "secret"
    get "/v3/current_organisation"
    assert_200
    data = JSON.parse(last_response.body)
    assert_equal "example.opinsys.net", data["domain"]
    assert_equal "cucumber", data["owners"][0]["username"]
  end

  it "can be fetched current organisation" do
    basic_authorize "cucumber", "cucumber"
    get "/v3/current_organisation"
    assert_200
    data = JSON.parse(last_response.body)
    assert_equal "example.opinsys.net", data["domain"]
    assert_equal "cucumber", data["owners"][0]["username"]
  end

  it "cannot be fetched by normal user" do
    basic_authorize "bob", "secret"
    get "/v3/organisations"
    data = JSON.parse(last_response.body)
    assert_equal 401, last_response.status
    assert data["error"]
    assert_equal data["error"]["code"], "Unauthorized"
  end


end

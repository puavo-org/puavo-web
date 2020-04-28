require_relative "./helper"

require "addressable/uri"
require "gssapi"
require "http"
require "open3"

describe PuavoRest::SSO do
  before(:each) do
    @orig_config = CONFIG.dup
    CONFIG.delete("default_organisation_domain")
    CONFIG["bootserver"] = false

    PuavoRest::Organisation.refresh
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
      :puavoEduPersonAffiliation => ["student"],
      :mail => "bob@example.com"
    )

    @group = Group.new
    @group.cn = "group1"
    @group.displayName = "Group 1"
    @group.puavoSchool = @school.dn
    @group.save!

    @role = Role.new
    @role.displayName = "Some role"
    @role.puavoSchool = @school.dn
    @role.groups << @group
    @role.save!

    @user.set_password "secret"
    @user.puavoSchool = @school.dn
    @user.role_ids = [ @role.puavoId ]
    @user.save!

  end

  after do
    system('kdestroy')  # remove the ticket obtained with kinit
    CONFIG = @orig_config
  end

  describe 'get resources using gssapi' do
    it 'user can get /v3/whoami with a kerberos ticket' do
      kinit_out, kinit_errmsg, kinit_status \
        = Open3.capture3('kinit', '-f', 'bob@EXAMPLE.PUAVO.NET',
                         stdin_data: "secret")
      assert_equal 0, kinit_status.exitstatus,
                   "kinit -f did not work for bob: #{ kinit_errmsg }"

      # This assumes we are running the test puavo-rest in localhost port
      # 9292.  It would be nicer if we could obtain this information from
      # somewhere (or could just use the rack-test get with gssapi).
      url = Addressable::URI.parse('http://localhost:9292/v3/whoami')
      gsscli = GSSAPI::Simple.new('localhost', 'HTTP')
      token = gsscli.init_context(nil, :delegate => true)
      http = HTTP.auth("Negotiate #{Base64.strict_encode64(token)}")
      response = http.get(url)
      data = JSON.parse(response.to_s)

      assert_equal 200, response.status
      assert_equal 'bob', data['username']
      assert_equal 'Bob', data['first_name']
      assert_equal 'Brown', data['last_name']
      assert_equal 'bob@example.com', data['email']
      assert_equal 'bob@EXAMPLE.PUAVO.NET', data['edu_person_principal_name']
    end
  end
end

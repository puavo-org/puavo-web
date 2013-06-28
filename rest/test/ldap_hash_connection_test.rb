require_relative "./helper"
require_relative "../ldap_hash"

describe "LdapHash connection management" do

  before(:each) do
    Puavo::Test.clean_up_ldap
    FileUtils.rm_rf PuavoRest::CONFIG["ltsp_server_data_dir"]
    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor"
    )

    @user = User.new(
      :givenName => "Bob",
      :sn  => "Brown",
      :uid => "bob",
      :puavoEduPersonAffiliation => "student",
      :mail => "bob@example.com"
    )
    @user.set_password "secret"
    @user.puavoSchool = @school.dn
    @user.role_ids = [
      Role.find(:first, :attribute => "displayName", :value => "Maintenance").puavoId
    ]
    @user.save!
  end

  it "can get current user with dn and password" do
    PuavoRest::LdapHash.setup(
      :credentials => {
        :dn => @user.dn,
        :password => "secret"
      },
      :organisation => PuavoRest::Organisation.by_domain["*"]
    )

    user = PuavoRest::User.current
    assert_equal "Bob", user["first_name"]
    assert_equal "bob", user["username"]
    assert_equal @user.dn, user["dn"]
  end

  it "can get current user with username and password" do
    PuavoRest::LdapHash.setup(
      :credentials => {
        :username => "bob",
        :password => "secret"
      },
      :organisation => PuavoRest::Organisation.by_domain["*"]
    )

    user = PuavoRest::User.current
    assert_equal "Bob", user["first_name"]
    assert_equal "bob", user["username"]
    assert_equal @user.dn, user["dn"]
  end

  it "can change current user temporally" do
    alice = User.new(
      :givenName => "Alice",
      :sn  => "Wonderland",
      :uid => "alice",
      :puavoEduPersonAffiliation => "student",
      :mail => "alice@example.com"
    )
    alice.set_password "secret2"
    alice.puavoSchool = @school.dn
    alice.role_ids = [
      Role.find(:first, :attribute => "displayName", :value => "Maintenance").puavoId
    ]
    alice.save!

    PuavoRest::LdapHash.setup(
      :credentials => {
        :username => "bob",
        :password => "secret"
      },
      :organisation => PuavoRest::Organisation.by_domain["*"]
    )

    assert_equal "Bob", PuavoRest::User.current["first_name"]

    PuavoRest::LdapHash.setup(
      :credentials => {
        :username => "alice",
        :password => "secret2"
      }) do

        assert_equal "Alice", PuavoRest::User.current["first_name"]
      end

    assert_equal "Bob", PuavoRest::User.current["first_name"]
  end
end

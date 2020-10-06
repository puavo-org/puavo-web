require_relative "./helper"
require_relative "../lib/ldapmodel"

describe "LdapModel connection management" do

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
      :email      => 'bob@example.com',
      :first_name => 'Bob',
      :last_name  => 'Brown',
      :password   => 'secret',
      :roles      => [ 'student' ],
      :school_dns => [ @school.dn.to_s ],
      :username   => 'bob',
    )
    @user.save!

    # XXX weird that this must be here
    @user.administrative_groups = [ maintenance_group.id ]
  end

  it "can get current user with dn and password" do
    LdapModel.setup(
      :credentials => {
        :dn => @user.dn.to_s,
        :password => "secret"
      },
      :organisation => PuavoRest::Organisation.default_organisation_domain!
    )

    user = PuavoRest::User.current
    assert_equal "Bob", user["first_name"]
    assert_equal "bob", user["username"]
    assert_equal @user.dn, user["dn"]
  end

  it "can get current user with username and password" do
    LdapModel.setup(
      :credentials => {
        :dn => @user.dn.to_s,
        :password => "secret"
      },
      :organisation => PuavoRest::Organisation.default_organisation_domain!
    )

    user = PuavoRest::User.current
    assert_equal "Bob", user["first_name"]
    assert_equal "bob", user["username"]
    assert_equal @user.dn, user["dn"]
  end

  it "can change current user temporally" do
    @alice = User.new(
      :givenName => "Alice",
      :sn  => "Wonderland",
      :uid => "alice",
      :puavoEduPersonAffiliation => "student",
      :mail => "alice@example.com"
    )
    @alice.set_password "secret2"
    @alice.puavoSchool = @school.dn
    @alice.role_ids = [
      Role.find(:first, :attribute => "displayName", :value => "Maintenance").puavoId
    ]
    @alice.save!

    LdapModel.setup(
      :credentials => {
        :dn => @user.dn.to_s,
        :password => "secret"
      },
      :organisation => PuavoRest::Organisation.default_organisation_domain!
    )

    assert_equal "Bob", PuavoRest::User.current["first_name"]

    LdapModel.setup(
      :credentials => {
        :dn => @alice.dn.to_s,
        :password => "secret2"
      }) do

        assert_equal "Alice", PuavoRest::User.current["first_name"]
      end

    assert_equal "Bob", PuavoRest::User.current["first_name"]
  end
end

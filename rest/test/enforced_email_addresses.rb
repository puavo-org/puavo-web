require_relative "./helper"

# I'm sorry
$enable_automatic = true

# Override this here, to "manually" enable enforced email addresses
def get_automatic_email(*args)
  return [$enable_automatic, 'hogwarts.magic']
end

describe LdapModel do
  before(:each) do
    Puavo::Test.clean_up_ldap
    setup_ldap_admin_connection()

    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor",
    )
  end

  describe "new user" do
    it "email is automatically set for new users that don't specify it" do
      user = PuavoRest::User.new
      user.first_name = 'Test'
      user.last_name = 'User'
      user.username = 'test.user1'
      user.roles = ['testuser']
      user.school_dns = [@school.dn.to_s]
      assert user.save!

      user = PuavoRest::User.by_dn!(user.dn)
      assert_equal user.email, ['test.user1@hogwarts.magic']
    end

    it "email is overridden for those new users who set it" do
      user = PuavoRest::User.new
      user.first_name = 'Test'
      user.last_name = 'User'
      user.username = 'test.user2'
      user.roles = ['testuser']
      user.school_dns = [@school.dn.to_s]
      user.email = 'foo@bar.com'
      assert user.save!

      user = PuavoRest::User.by_dn!(user.dn)
      assert_equal user.email, ['test.user2@hogwarts.magic']
    end

    it "multiple emails are ignored" do
      user = PuavoRest::User.new
      user.first_name = 'Test'
      user.last_name = 'User'
      user.username = 'test.user3'
      user.roles = ['testuser']
      user.school_dns = [@school.dn.to_s]
      user.email = ['foo@bar.com', 'another@address.com']
      assert user.save!

      user = PuavoRest::User.by_dn!(user.dn)
      assert_equal user.email, ['test.user3@hogwarts.magic']
    end
  end

  describe "existing user" do
    before(:each) do
      @user1 = PuavoRest::User.new(
        :first_name => 'Test',
        :last_name  => 'User',
        :username   => 'test.user1',
        :roles      => ['testuser'],
        :school_dns => [@school.dn.to_s],
      )
      assert @user1.save!

      # I'm sorry
      $enable_automatic = false

      @user2 = PuavoRest::User.new(
        :first_name => 'Test',
        :last_name  => 'User',
        :username   => 'test.user2',
        :roles      => ['testuser'],
        :school_dns => [@school.dn.to_s],
        :email      => 'foo@bar.com'
      )
      assert @user2.save!

      @user3 = PuavoRest::User.new(
        :first_name => 'Test',
        :last_name  => 'User',
        :username   => 'test.user3',
        :roles      => ['testuser'],
        :school_dns => [@school.dn.to_s],
        :email      => 'bar@quux.com',
      )
      assert @user3.save!

      # Please don't hate me
      $enable_automatic = true
    end

    it "simply saving the user object is enough to update the email address" do
      user = PuavoRest::User.by_dn!(@user1.dn)
      assert user.save!
      user = PuavoRest::User.by_dn!(@user1.dn)
      assert_equal user.email, ['test.user1@hogwarts.magic']

      user = PuavoRest::User.by_dn!(@user2.dn)
      assert_equal user.email, ['foo@bar.com']
      assert user.save!
      user = PuavoRest::User.by_dn!(@user2.dn)
      assert_equal user.email, ['test.user2@hogwarts.magic']

      user = PuavoRest::User.by_dn!(@user3.dn)
      assert_equal user.email, ['bar@quux.com']
      assert user.save!
      user = PuavoRest::User.by_dn!(@user3.dn)
      assert_equal user.email, ['test.user3@hogwarts.magic']
    end

    it "manual changes to email addresses are ignored" do
      user = PuavoRest::User.by_dn!(@user1.dn)
      user.email = 'foo@foo.foo'

      assert user.save!

      user = PuavoRest::User.by_dn!(@user1.dn)
      assert_equal user.email, ['test.user1@hogwarts.magic']
    end

    it "can't clear email address" do
      user = PuavoRest::User.by_dn!(@user1.dn)
      user.email = nil
      assert user.save!

      user = PuavoRest::User.by_dn!(@user1.dn)
      assert_equal user.email, ['test.user1@hogwarts.magic']
    end

    it "username changes update the email address" do
      user = PuavoRest::User.by_dn!(@user1.dn)
      user.username = 'youre.a.wizard'
      assert user.save!

      user = PuavoRest::User.by_dn!(@user1.dn)
      assert_equal user.email, ['youre.a.wizard@hogwarts.magic']
    end
  end
end

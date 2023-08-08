require_relative "./helper"
require_relative "../lib/external_login_test_config"

def assert_external_status(username, password, expected_status, errmsg)
  basic_authorize username, password
  post '/v3/external_login/auth'
  assert_200
  parsed_response = JSON.parse(last_response.body)
  assert_equal expected_status,
               parsed_response['status'],
               errmsg
end

def assert_password(user, password, errmsg, result_if_success=true)
  begin
    user.bind(password)
    user.remove_connection
    assert result_if_success, errmsg
  rescue StandardError => e
    assert !result_if_success, errmsg
  end
end

def assert_password_not(user, password, errmsg)
  assert_password(user, password, errmsg, false)
end

def assert_user_belongs_to_an_administrative_group(username, groupname)
  group = Group.find(:first, :attribute => 'cn', :value => groupname)
  assert !group.nil?, "There is no #{ groupname } group when there should be"

  assert_equal group.puavoEduGroupType,
               'administrative group',
               "#{ groupname } group is not an administrative group"
  assert Array(group.memberUid).include?(username),
         "#{ username } does not belong to the #{ groupname } group"
end

def assert_user_belongs_to_one_group_of_type(username, grouptype, group_regex)
  groups = Group.find(:all,
                      :attribute => 'puavoEduGroupType',
                      :value     => grouptype)
  assert !groups.nil?, "no groups of type #{ grouptype }"

  membership_groups = Array(groups).select do |group|
                        Array(group.memberUid).include?(username)
                      end
  assert_equal 1,
               membership_groups.count,
               "user #{ username } belongs to #{ membership_groups.count }" \
                 + " groups of type #{ grouptype } instead of just one"

  membership_group = membership_groups.first
  assert membership_group.cn.match(group_regex),
         "user #{ username } group #{ membership_group.cn }" \
           + " does not match #{ group_regex }"
end

describe PuavoRest::ExternalLogin do
  # We store this as json to get deep copy semantics, so we have the freedom
  # to mess with external login configurations in tests.
  orig_config = CONFIG.dup
  orig_default_host = Rack::Test::DEFAULT_HOST

  before(:each) do
    Rack::Test::DEFAULT_HOST = 'external.puavo.net'
    CONFIG = orig_config.dup
    CONFIG['external_login'] \
      = PuavoRest::ExternalLoginTestConfig::get_configuration()

    Puavo::Test.clean_up_ldap
    Puavo::Test.setup_test_connection('external')

    @heroes_school = School.create(:cn          => 'heroes-u',
                                   :displayName => 'Heroes University')
    @heroes_school.save!

    @star_school = School.create(:cn          => 'stars',
                                 :displayName => 'Stars')
    @star_school.save!

    CONFIG['external_login']['external']['external_ldap']['user_mappings'] \
          ['defaults']['school_dns'] = [ @heroes_school.dn.to_s ]
  end

  after do
    CONFIG = orig_config.dup
    Puavo::Test.clean_up_ldap
    Rack::Test::DEFAULT_HOST = orig_default_host
  end

  describe 'logins with bad credentials fail' do
    it 'provide no credentials' do
      post '/v3/external_login/auth'
      assert_200
      parsed_response = JSON.parse(last_response.body)
      assert_equal 'BADUSERCREDS',
                   parsed_response['status'],
                   'missing credentials did not return BADUSERCREDS'
    end

    it 'fails with bad username' do
      assert_external_status('badusername',
                             'badpassword',
                             'BADUSERCREDS',
                             'expected BADUSERCREDS as external_login status')
    end

    it 'fails with bad password' do
      assert_external_status('luke.skywalker',
                             'badpassword',
                             'BADUSERCREDS',
                             'expected BADUSERCREDS as external_login status')
      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      assert_nil user,
                 'user luke.skywalker was created to Puavo, should not be'
    end
  end

  describe 'tests with good login credentials' do
    before :each do
      assert_external_status('luke.skywalker',
                             'secret',
                             'UPDATED',
                             'expected UPDATED as external_login status')
      @user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      assert !@user.nil?, 'user luke.skywalker could not be found in Puavo'
    end

    it 'user information is correct after successful login' do
      assert_equal 'luke.skywalker',
                   @user.uid,
                   'luke.skywalker has incorrect uid'
      assert_equal 'Luke',
                   @user.given_name,
                   'luke.skywalker has incorrect given name'
      assert_equal 'Skywalker',
                   @user.surname,
                   'luke.skywalker has incorrect surname'
      assert_equal 'luke.skywalker@HEROES.PUAVO.NET',
                   @user.puavoExternalId,
                   'luke.skywalker has incorrect external_id'
      assert_equal 'Skywalker',
                   @user.puavoLearnerId,
                   'luke.skywalker has incorrect learner_id'
    end

    it 'user password is synced to Puavo' do
      assert !@user.nil?, 'user luke.skywalker could not be found in Puavo'
      assert_password @user, 'secret', 'password was not valid'
    end

    it 'subsequent login with bad password fails' do
      assert_external_status('luke.skywalker',
                             'badpassword',
                             'BADUSERCREDS',
                             'expected BADUSERCREDS as external_login status')

      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      assert !user.nil?, 'user luke.skywalker could not be found in Puavo'
    end

    it 'subsequent successful login returns NOCHANGE' do
      assert_external_status('luke.skywalker',
                             'secret',
                             'NOCHANGE',
                             'expected NOCHANGE as external_login status')

      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      assert !user.nil?, 'user luke.skywalker could not be found in Puavo'
    end

    it 'user is in expected school' do
      assert_equal @heroes_school.dn.to_s, @user.puavoSchool
    end

    it 'user has expected roles' do
      assert_equal 'student', @user.puavoEduPersonAffiliation
    end

    it 'user belongs to a "heroes"-administrative group' do
      assert_user_belongs_to_an_administrative_group('luke.skywalker', 'heroes')
    end

    it 'user belongs to some teaching group' do
      assert_user_belongs_to_one_group_of_type('luke.skywalker',
                                               'teaching group',
                                               /^heroes-(\d+)-(\d+)$/)
    end

    it 'user belongs to some yearclass group' do
      assert_user_belongs_to_one_group_of_type('luke.skywalker',
                                               'year class',
                                               /^heroes-(\d+)$/)
    end
  end

  describe 'tests with a special user' do
    before :each do
      assert_external_status('sarah.connor',
                             'secret',
                             'UPDATED',
                             'expected UPDATED as external_login status')
      @user = User.find(:first, :attribute => 'uid', :value => 'sarah.connor')
      assert !@user.nil?, 'user sarah.connor could not be found in Puavo'
    end

    it 'user is in expected school' do
      assert_equal @heroes_school.dn.to_s, @user.puavoSchool
    end

    it 'user has expected roles' do
      assert_equal 'teacher', @user.puavoEduPersonAffiliation
    end

    it 'user belongs to a "heroes"-administrative group' do
      assert_user_belongs_to_an_administrative_group('sarah.connor', 'heroes')
    end

    it 'user belongs to a "resistence"-administrative group' do
      assert_user_belongs_to_an_administrative_group('sarah.connor',
                                                     'resistence')
    end

    it 'user belongs to some teaching group' do
      assert_user_belongs_to_one_group_of_type('sarah.connor',
                                               'teaching group',
                                               /^heroes-(\d+)-(\d+)$/)
    end

    it 'user belongs to some yearclass group' do
      assert_user_belongs_to_one_group_of_type('sarah.connor',
                                               'year class',
                                               /^heroes-(\d+)$/)
    end
  end

  describe 'user information is updated as it should on subsequent logins' do
    before :each do
      assert_external_status('luke.skywalker',
                             'secret',
                             'UPDATED',
                             'expected UPDATED as external_login status')
    end

    it 'subsequent successful logins update user information when changed' do
      # change Luke Skywalker --> Luke Starkiller and see that login fixes that
      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      user.surname = 'Starkiller'
      user.save!

      assert_external_status('luke.skywalker',
                             'secret',
                             'UPDATED',
                             'expected UPDATED as external_login status')
      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      assert_equal 'Skywalker',
                   user.surname,
                   'Luke Skywalker is no longer Skywalker'
    end

    it 'subsequent successful logins update username when changed' do
      # change luke.skywalker --> luke.skywalker2 (username) and see that login
      # fixes that
      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      external_id = user.puavoExternalId
      user.uid = 'luke.skywalker2'
      user.save!

      assert_external_status('luke.skywalker',
                             'secret',
                             'UPDATED',
                             'login with mismatching username did not succeed')

      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      assert !user.nil?, 'luke.skywalker could not be found from Puavo'
      assert_equal 'luke.skywalker',
                   user.uid,
                   'luke.skywalker username was not changed according' \
                     + ' to external auth service'
      assert_equal external_id,
                   user.puavoExternalId,
                   'luke.skywalker external id has unexpectedly changed'
    end

    it 'user password is invalidated on login with nonmatching password' do
      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      # set password to not match the one in external service
      user.password_change_mode = :no_upstream
      user.set_password 'oldpassword'
      user.save!

      assert_password(user, 'oldpassword', 'password not changed in Puavo')

      assert_external_status('luke.skywalker',
                             'oldpassword',
                             'UPDATED_BUT_FAIL',
                             'login password not invalidated')

      msg = 'password "oldpassword" was valid,' \
              + ' even though password should have been invalidated'
      assert_password_not(user, 'oldpassword', msg)
      msg = 'password "secret" was valid,' \
              + ' even though password should have been invalidated'
      assert_password_not(user, 'secret', msg)

      assert_external_status('luke.skywalker',
                             'secret',
                             'UPDATED',
                             'login with correct password did not work')

      assert_password(user,
                      'secret',
                      'password "secret" was not valid,' \
                        + ' even though it should work again')
    end

    it 'user password is invalidated when mismatching username is used' do
      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      # make usernames mismatch
      user.uid = 'luke.skywalker2'
      user.save!

      assert_password(user, 'secret', 'password "secret" was not valid')

      # login with wrong username and wrong password
      user.uid = 'luke.skywalker2'
      assert_external_status('luke.skywalker2',
                             'badpassword',
                             'BADUSERCREDS',
                             'can login with a wrong Puavo username/password')

      # password not invalidated
      assert_password(user, 'secret', 'password "secret" was not valid')

      # login with wrong username but correct password
      # (because there is a username with matching external id, we can know
      # that wrong username was used)
      assert_external_status('luke.skywalker2',
                             'secret',
                             'UPDATED_BUT_FAIL',
                             'can login with a wrong Puavo username')

      # password was invalidated as it should
      assert_password_not(user,
                          'secret',
                          'password "secret" should not be valid anymore' \
                            + ' (username mismatch)')

      # login again with correct username/password
      assert_external_status('luke.skywalker',
                             'secret',
                             'UPDATED',
                             'login with correct username/password failed')

      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      assert_password(user, 'secret', 'password "secret" was not valid')
    end

    it 'user that has been removed from external login is marked as removed' do
      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      # first check that user is not marked as "to be removed"
      assert_nil user.puavoRemovalRequestTime,
                 'user removal request time is set when it should not be'

      # disassociate user "luke.skywalker" from external login service
      old_external_id = user.puavoExternalId
      user.puavoExternalId = 'NOTANACTUALEXTERNALID'
      user.uid = 'luke.skywalker2'
      user.save!

      # now we have a user does not exist in external login service

      assert_external_status('luke.skywalker2',
                             'secret',
                             'BADUSERCREDS',
                             'can login to user that does not exist externally')

      # check that user is marked as "to be removed"
      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker2')
      assert !user.puavoRemovalRequestTime.nil?,
             'user removal request time is not set when it should be'
      assert_equal user.puavoRemovalRequestTime.class,
                   Time,
                   'user removal request time is of wrong type'

      # Check we can get the user back after a new login, in case the user
      # reappears in external login service (point our external id back to
      # the correct user).
      user.puavoExternalId = old_external_id
      user.save!

      assert_external_status('luke.skywalker',
                             'secret',
                             'UPDATED',
                             'can not login again when scheduled for removal')

      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      assert_nil user.puavoRemovalRequestTime,
                 'user removal request time is set when it should not be'
    end

    it 'user schools, groups and roles follow configuration changes' do
      CONFIG['external_login']['external']['external_ldap']['user_mappings'] \
            ['by_dn'] = [
        { '*,ou=People,dc=edu,dc=heroes,dc=net' => [
            { 'add_administrative_group' => {
                'displayname' => 'Better heroes',
                'name'        => 'better-heroes', }},
            { 'add_roles' => [ 'teacher' ] },
            { 'add_school_dns' => [ @star_school.dn.to_s ] },
            { 'add_teaching_group' => {
                'displayname' => 'Better heroes school %GROUP',
                'name'        => 'better-heroes-%STARTYEAR-%GROUP', }},
            { 'add_year_class' => {
                'displayname' => 'Better heroes school %CLASSNUMBER',
                'name'        => 'better-heroes-%STARTYEAR', }}]}]

      assert_external_status('luke.skywalker', 'secret', 'UPDATED', 'login error')

      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      assert !user.nil?, 'luke.skywalker could not be found from Puavo'

      assert_equal @star_school.dn.to_s, user.puavoSchool
      assert_equal 'teacher', user.puavoEduPersonAffiliation

      assert_user_belongs_to_an_administrative_group('luke.skywalker',
                                                     'better-heroes')
      group = Group.find(:first, :attribute => 'cn', :value => 'heroes')
      assert !group.nil?, 'There is no heroes group when there should be'
      assert !Array(group.memberUid).include?('luke.skywalker'),
             "luke.skywalker does belong to the \"heroes\"-group"

      assert_user_belongs_to_one_group_of_type('luke.skywalker',
                                               'teaching group',
                                               /^better-heroes-(\d+)-(\d+)$/)
      assert_user_belongs_to_one_group_of_type('luke.skywalker',
                                               'year class',
                                               /^better-heroes-(\d+)$/)
    end
  end

  describe 'test group creation and membership handling' do
    it 'new groups are created as users log in' do
      group = Group.find(:first, :attribute => 'cn', :value => 'heroes')
      assert_nil group, 'There is a heroes group when it should not be (yet)'

      assert_external_status('luke.skywalker',
                             'secret',
                             'UPDATED',
                             'login error')

      group = Group.find(:first, :attribute => 'cn', :value => 'heroes')
      assert !group.nil?, 'There is no heroes group when there should be'
      assert_equal %w(luke.skywalker),
                   Array(group.memberUid),
                   'heroes group should consist of luke.skywalker'
    end

    it 'new members are added to groups as users log in' do
      assert_external_status('luke.skywalker',
                             'secret',
                             'UPDATED',
                             'login error')
      assert_external_status('lara.croft', 'secret', 'UPDATED', 'login error')

      group = Group.find(:first, :attribute => 'cn', :value => 'heroes')
      assert !group.nil?, 'There is no heroes group when there should be'
      assert_equal %w(luke.skywalker lara.croft),
                   group.memberUid,
                   'heroes group should consist of luke.skywalker' \
                     + ' and lara.croft'
    end

    it 'users are removed from groups according to configuration' do
      assert_external_status('luke.skywalker',
                             'secret',
                             'UPDATED',
                             'login error')
      assert_external_status('lara.croft', 'secret', 'UPDATED', 'login error')

      # remove all mappings so that luke.skywalker & lara.croft should
      # no longer belong to the group
      CONFIG['external_login']['external']['external_ldap']['user_mappings'] \
            ['by_dn'] = []

      assert_external_status('luke.skywalker',
                             'secret',
                             'UPDATED',
                             'login error')

      group = Group.find(:first, :attribute => 'cn', :value => 'heroes')
      assert_equal %w(lara.croft),
                   Array(group.memberUid),
                   'heroes group should consist of lara.croft only' \
                     + ' after disappearance of luke.skywalker'

      assert_external_status('lara.croft', 'secret', 'UPDATED', 'login error')

      group = Group.find(:first, :attribute => 'cn', :value => 'heroes')
      assert_equal [],
                   Array(group.memberUid),
                   'heroes group should not have any members'
    end
  end

  describe 'testing some error situations' do
    it 'external logins are not configured' do
      CONFIG.delete('external_login')
      assert_external_status('luke.skywalker',
                             'secret',
                             'NOTCONFIGURED',
                             'not returning NOTCONFIGURED when not configured')
    end

    it 'Puavo organisation admin credentials are wrong' do
      CONFIG['external_login']['external']['admin_password'] = 'thisisabadpw'
      assert_external_status('luke.skywalker',
                             'secret',
                             'CONFIGERROR',
                             'not returning CONFIGERROR on configuration error')
    end

    it 'external login service lookup credentials are wrong' do
      CONFIG['external_login']['external']['external_ldap']['bind_password'] \
        = 'thisisabadpw'
      assert_external_status('luke.skywalker',
                             'secret',
                             'UNAVAILABLE',
                             'not returning UNAVAILABLE on configuration error')
    end

    it 'trying to login as user only in Puavo' do
      # "cucumber"-user is NOT "heroes"-database (external login service)
      assert_external_status('cucumber',
                             'badpassword',
                             'NOTCONFIGURED',
                             'login error')

      assert_external_status('cucumber',
                             'cucumber',
                             'NOTCONFIGURED',
                             'login error')

      user = User.find(:first, :attribute => 'uid', :value => 'cucumber')
      assert !user.nil?, 'cucumber has disappeared from Puavo'

      assert_nil user.puavoExternalId,
                 'cucumber has an external id even though she should not'
    end

    it 'trying to login as user whose external id has gone missing' do
      assert_external_status('luke.skywalker',
                             'secret',
                             'UPDATED',
                             'login error')
      # "luke.skywalker IS on "heroes"-database (external login service)
      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      assert !user.nil?, 'luke.skywalker is not in Puavo'
      user.puavoExternalId = nil
      user.save!

      assert_external_status('luke.skywalker',
                             'badpassword',
                             'NOTCONFIGURED',
                             'unmanaged user managed by external login')
      assert_external_status('luke.skywalker',
                             'secret',
                             'NOTCONFIGURED',
                             'unmanaged user managed by external login')

      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      assert !user.nil?, 'luke.skywalker is not in Puavo'
      assert_nil user.puavoExternalId,
                 'luke.skywalker has an external id even though he should not'
    end

    it 'we have mismatching external ids for the same username' do
      assert_external_status('luke.skywalker',
                             'secret',
                             'UPDATED',
                             'login error')
      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      # disassociate user "luke.skywalker" from external login service
      old_external_id = user.puavoExternalId
      user.puavoExternalId = 'NOTANACTUALEXTERNALID'
      user.save!

      assert_external_status('luke.skywalker',
                             'secret',
                             'UPDATEERROR',
                             'username conflict did not trigger UPDATEERROR')
    end

    it 'trying to use external service that does not respond' do
      CONFIG['external_login']['external']['external_ldap']['server'] \
        = 'nonexistent.example.com'

      assert_external_status('luke.skywalker',
                             'secret',
                             'UNAVAILABLE',
                             'external server was not UNAVAILABLE')
    end

    it 'trying to configure a user to two teaching groups' do
      CONFIG['external_login']['external']['external_ldap']['user_mappings'] \
            ['by_dn'] = [
        { '*,ou=People,dc=edu,dc=heroes,dc=net' => [
            { 'add_teaching_group' => {
                'displayname' => 'Heroes school %GROUP',
                'name'        => 'heroes-%STARTYEAR-%GROUP', }},
            { 'add_teaching_group' => {
                'displayname' => 'Another heroes school %GROUP',
                'name'        => 'another-heroes-%STARTYEAR-%GROUP', }}]}]

      assert_external_status('luke.skywalker',
                             'secret',
                             'UPDATED',
                             'login error')

      groups = Group.find(:all,
                          :attribute => 'puavoEduGroupType',
                          :value     => 'teaching group')
      assert groups.empty?,
             'there are teaching groups even when there should be none'
    end

    it 'trying to configure a user to two year class groups' do
      CONFIG['external_login']['external']['external_ldap']['user_mappings'] \
            ['by_dn'] = [
        { '*,ou=People,dc=edu,dc=heroes,dc=net' => [
            { 'add_year_class' => {
                'displayname' => 'Heroes school %CLASSNUMBER',
                'name'        => 'heroes-%STARTYEAR', }},
            { 'add_year_class' => {
                'displayname' => 'Another heroes school %CLASSNUMBER',
                'name'        => 'another-heroes-%STARTYEAR', }}]}]

      assert_external_status('luke.skywalker',
                             'secret',
                             'UPDATED',
                             'login error')

      groups = Group.find(:all,
                          :attribute => 'puavoEduGroupType',
                          :value     => 'year class')
      assert groups.empty?,
             'there are year class groups even when there should be none'
    end
  end

  describe 'tests for cases where external login is for authentication only' do
    before :each do
      CONFIG['external_login']['external']['manage_puavousers'] = false
    end

    it 'authonly test fails with bad username' do
      assert_external_status('badusername', 'badpassword', 'PUAVOUSERMISSING',
        'expected PUAVOUSERMISSING as external_login status')
    end

    it 'authonly test does not create user with bad password' do
      assert_external_status('luke.skywalker', 'badpassword',
        'PUAVOUSERMISSING',
        'expected PUAVOUSERMISSING as external_login status')
      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      assert_nil user,
                 'user luke.skywalker was created to Puavo, should not be'
    end

    it 'authonly test does not create user with good password' do
      assert_external_status('luke.skywalker', 'secret', 'PUAVOUSERMISSING',
        'expected PUAVOUSERMISSING as external_login status')
      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      assert_nil user,
                 'user luke.skywalker was created to Puavo, should not be'
    end

    it 'authonly test fails with bad password even when user exists' do
      user = User.create(
               :givenName                   => 'Luke',
               :puavoEduPersonAffiliation   => 'testuser',
               :puavoEduPersonPrimarySchool => @heroes_school.dn,
               :puavoSchool                 => [ @heroes_school.dn ],
               :sn                          => 'Starkiller',
               :uid                         => 'luke.skywalker')
      user.save!

      # when external id is missing, we should get NOTCONFIGURED
      assert_external_status('luke.skywalker', 'badpassword', 'NOTCONFIGURED',
        'expected BADUSERCREDS as external_login status')

      user.puavoExternalId = 'luke.skywalker@HEROES.PUAVO.NET'
      user.save!

      # with external id, things should behave more normally
      assert_external_status('luke.skywalker', 'badpassword', 'BADUSERCREDS',
        'expected BADUSERCREDS as external_login status')

      # user information must not have changed
      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      assert_equal(user.sn, 'Starkiller')
    end

    it 'authonly test does not update user info when login ok' do
      user = User.create(
        :givenName                   => 'Luke',
        :puavoEduPersonAffiliation   => 'testuser',
        :puavoEduPersonPrimarySchool => @heroes_school.dn,
        :puavoExternalId             => 'luke.skywalker@HEROES.PUAVO.NET',
        :puavoSchool                 => [ @heroes_school.dn ],
        :sn                          => 'Starkiller',
        :uid                         => 'luke.skywalker')
      user.save!
      old_password = user.userPassword

      # when good password, login should be successful
      assert_external_status('luke.skywalker', 'secret', 'UPDATED',
        'expected UPDATED as external_login status')

      # user information must not have changed
      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      assert_equal(user.sn, 'Starkiller')

      assert old_password != user.userPassword,
             'user password should be set to puavo during external login'
    end

    it 'authonly test invalidates user password if external login fails' do
      user = User.create(
        :givenName                   => 'Luke',
        :puavoEduPersonAffiliation   => 'testuser',
        :puavoEduPersonPrimarySchool => @heroes_school.dn,
        :puavoExternalId             => 'luke.skywalker@HEROES.PUAVO.NET',
        :puavoSchool                 => [ @heroes_school.dn ],
        :sn                          => 'Starkiller',
        :uid                         => 'luke.skywalker')
      user.save!
      user.password_change_mode = :no_upstream
      user.set_password 'oldpassword'
      user.save!

      assert_password(user, 'oldpassword', 'password not changed in Puavo')

      assert_external_status('luke.skywalker',
                             'oldpassword',
                             'UPDATED_BUT_FAIL',
                             'login password not invalidated (matching uid)')

      msg = 'password "oldpassword" was valid,' \
              + ' even though password should have been invalidated'
      assert_password_not(user, 'oldpassword', msg)
      msg = 'password "secret" was valid,' \
              + ' even though password should have been invalidated'
      assert_password_not(user, 'secret', msg)

      assert_external_status('luke.skywalker', 'secret', 'UPDATED',
        'login with correct password works (matching uid)')

      assert_password(user, 'secret', 'password "secret" should be valid again')

      # Invalidation should also happen when usernames mismatch (we can
      # lookup the correct external uid with external id).
      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      user.uid = 'luke.starkiller'
      user.save!

      user.password_change_mode = :no_upstream
      user.set_password 'oldpassword'
      user.save!

      assert_external_status('luke.starkiller', 'oldpassword',
        'UPDATED_BUT_FAIL',
        'password is invalidated even when when username mismatches')
    end

    it 'in authonly case, disappeared users are not marked as to be removed' do
      user = User.create(
        :givenName                   => 'Luke',
        :puavoEduPersonAffiliation   => 'testuser',
        :puavoEduPersonPrimarySchool => @heroes_school.dn,
        :puavoExternalId             => 'luke.skywalker@HEROES.PUAVO.NET',
        :puavoSchool                 => [ @heroes_school.dn ],
        :sn                          => 'Starkiller',
        :uid                         => 'luke.skywalker')
      user.save!

      # disassociate user "luke.skywalker" from external login service
      old_external_id = user.puavoExternalId
      user.puavoExternalId = 'NOTANACTUALEXTERNALID'
      user.uid = 'luke.skywalker2'
      user.save!

      assert_external_status('luke.skywalker2', 'secret', 'BADUSERCREDS',
        'can not login to user that does not exist externally')

      # check that user is *not* marked as "to be removed"
      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker2')
      assert_nil(user.puavoRemovalRequestTime,
                 'user removal request time is set when it not should be')
    end
  end

  describe 'some tests with learner_id as extlogin id' do
    before :each do
      CONFIG['external_login']['external']['external_ldap'] \
            ['extlogin_id_field'] = 'sn'
      CONFIG['external_login']['external']['puavo_extlogin_id_field'] \
        = 'learner_id'
      assert_external_status('luke.skywalker',
                             'secret',
                             'UPDATED',
                             'expected UPDATED as external_login status')
      @user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      assert !@user.nil?, 'user luke.skywalker could not be found in Puavo'
    end

    it 'user information is correct after successful login (learner_id)' do
      assert_equal 'luke.skywalker',
                   @user.uid,
                   'luke.skywalker has incorrect uid'
      assert_equal 'Luke',
                   @user.given_name,
                   'luke.skywalker has incorrect given name'
      assert_equal 'Skywalker',
                   @user.surname,
                   'luke.skywalker has incorrect surname'
      # We use surname to simulate the learner id, because we know it
      # and in our database it is unique for each user.
      assert_equal 'Skywalker',
                   @user.puavoLearnerId,
                   'luke.skywalker has incorrect learner_id'
    end

    it 'user password is synced to Puavo (using learner_id)' do
      assert !@user.nil?, 'user luke.skywalker could not be found in Puavo'
      assert_password @user, 'secret', 'password was not valid'
    end

    it 'subsequent login with bad password fails (learner_id)' do
      assert_external_status('luke.skywalker',
                             'badpassword',
                             'BADUSERCREDS',
                             'expected BADUSERCREDS as external_login status')

      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      assert !user.nil?, 'user luke.skywalker could not be found in Puavo'
    end

    it 'subsequent successful login returns NOCHANGE (learner_id)' do
      assert_external_status('luke.skywalker',
                             'secret',
                             'NOCHANGE',
                             'expected NOCHANGE as external_login status')

      user = User.find(:first, :attribute => 'uid', :value => 'luke.skywalker')
      assert !user.nil?, 'user luke.skywalker could not be found in Puavo'
    end
  end

  describe 'some tests with puavo_id as extlogin id' do
    it 'user information is correct after successful login (puavo_id)' do
      # Use puavoId as external link attribute.
      CONFIG['external_login']['external']['external_ldap'] \
            ['extlogin_id_field'] = 'puavoId'
      CONFIG['external_login']['external']['puavo_extlogin_id_field'] = 'id'

      # Then check that when using puavoId as external id, using creation
      # does not work.
      assert_external_status('lara.croft',
                             'secret',
                             'UPDATEERROR',
                             'expected UPDATEERROR as external_login status')

      # Check the puavoId of "lara.croft" (in external ldap).
      external_lara = PuavoRest::ExternalLoginTestConfig.get_entry_from_cn(
                        'dc=edu,dc=heroes,dc=net', 'lara.croft')
      external_lara_puavo_id = external_lara[:puavoId]

      # Create Lara but with slightly mismatching info.
      lara = User.create(
               :givenName                   => 'Lara',
               :puavoId                     => external_lara_puavo_id,
               :puavoEduPersonAffiliation   => 'testuser',
               :puavoEduPersonPrimarySchool => @heroes_school.dn,
               :puavoSchool                 => [ @heroes_school.dn ],
               :sn                          => 'Starkiller',
               :uid                         => 'lara.skywalker')
      lara.save!

      # Login as "lara.croft".
      assert_external_status('lara.croft',
                             'secret',
                             'UPDATED',
                             'expected UPDATE as external_login status')

      # Check that Lara has changed info.
      lara = User.find(:first, :attribute => 'uid', :value => 'lara.croft')

      assert_equal 'lara.croft',
                   lara.uid,
                   'lara.croft has incorrect uid'
      assert_equal 'Lara',
                   lara.given_name,
                   'lara.croft has incorrect given name'
      assert_equal 'Croft',
                   lara.surname,
                   'lara.croft has incorrect surname'
      assert_equal Integer(Array(external_lara_puavo_id).first),
                   lara.puavoId,
                   'lara.croft has incorrect puavoId'
    end
  end
end

require_relative "./helper"

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

describe PuavoRest::ExternalLogin do
  # XXX where does this one come from?
  extuser_target_school_dn = 'puavoId=5,ou=Groups,dc=edu,dc=example,dc=fi'

  before(:each) do
    @orig_config = CONFIG.dup

    org_conf_path = '../../../config/organisations.yml'
    organisations = YAML.load_file(File.expand_path(org_conf_path, __FILE__))

    CONFIG['external_login'] = {
      'example' => {
        # XXX admin_dn is "cucumber" dn, but how to get it nicely
        # XXX so it is always correct?
        'admin_dn'       => 'puavoId=8,ou=People,dc=edu,dc=example,dc=fi',
        'admin_password' => organisations['example']['owner_pw'],
        'service'        => 'external_ldap',
        'external_ldap'  => {
          'base'                    => 'dc=edu,dc=heroes,dc=fi',
          # XXX admin_dn is "admin" dn, but how to get it nicely
          # XXX so it is always correct?
          # XXX (we could also use some special user which only has some read
          # XXX permissions to People)
          'bind_dn'                 => 'puavoId=16,ou=People,dc=edu,dc=heroes,dc=fi',
          'bind_password'           => organisations['heroes']['owner_pw'],
          'dn_mappings'    => {
            'defaults' => {
              'classnumber_regex'    => '(\\d)$', # typically: '^(\\d+)'
              'roles'                => [ 'student' ],
              'school_dns'           => [ extuser_target_school_dn ],
              'teaching_group_field' => 'gidNumber', # typically: 'department'
            },
            'mappings' => [
              { '*,ou=People,dc=edu,dc=heroes,dc=fi' => [
                  { 'add_administrative_group' => {
                      'displayname' => 'Heroes',
                      'name'        => 'heroes', }},
                  { 'add_teaching_group' => {
                      'displayname' => 'Heroes school %GROUP',
                      'name'        => 'heroes-%STARTYEAR-%GROUP', }},
                  { 'add_year_class' => {
                      'displayname' => 'Heroes school %CLASSNUMBER',
                      'name'        => 'heroes-%STARTYEAR', }},
                ]},
              { 'puavoId=62,ou=People,dc=edu,dc=heroes,dc=fi' => [
                  { 'add_administrative_group' => {
                      'displayname' => 'Resistence',
                      'name'        => 'resistence', }},
                  { 'add_roles' => [ 'teacher' ] },
                ]},
            ],
          },
          'external_domain'         => 'example.com',
          'external_id_field'       => 'eduPersonPrincipalName',
          'external_username_field' => 'mail',
          'server'                  => 'localhost',
        },
      }
    }

    Puavo::Test.clean_up_ldap
  end

  after do
    CONFIG = @orig_config
  end

  describe 'logins with bad credentials fail' do
    it 'fails with bad username' do
      assert_external_status('badusername',
                             'badpassword',
                             'BADUSERCREDS',
                             'expected BADUSERCREDS as external_login status')
    end

    it 'fails with bad password' do
      assert_external_status('peter.parker',
                             'badpassword',
                             'BADUSERCREDS',
                             'expected BADUSERCREDS as external_login status')
      user = User.find(:first, :attribute => 'uid', :value => 'peter.parker')
      assert_nil user, 'user peter.parker was created to Puavo, should not be'
    end
  end

  describe 'tests with good login credentials' do
    before :each do
      assert_external_status('peter.parker',
                             'secret',
                             'UPDATED',
                             'expected UPDATED as external_login status')
    end

    it 'login succeeds with good username/password' do
      user = User.find(:first, :attribute => 'uid', :value => 'peter.parker')
      assert !user.nil?, 'user peter.parker could not be found in Puavo'
      assert_equal 'peter.parker',
                   user.uid,
                   'peter.parker has incorrect uid'
      assert_equal 'Peter',
                   user.given_name,
                   'peter.parker has incorrect given name'
      assert_equal 'Parker',
                   user.surname,
                   'peter.parker has incorrect surname'
      assert_equal 'peter.parker@HEROES.OPINSYS.NET',
                   user.puavoExternalId,
                   'peter.parker has incorrect external_id'
      assert_password user, 'secret', 'password was not valid'
    end

    it 'subsequent login with bad password fails' do
      assert_external_status('peter.parker',
                             'badpassword',
                             'BADUSERCREDS',
                             'expected BADUSERCREDS as external_login status')

      user = User.find(:first, :attribute => 'uid', :value => 'peter.parker')
      assert !user.nil?, 'user peter.parker could not be found in Puavo'
    end

    it 'subsequent successful logins behave expectedly' do
      assert_external_status('peter.parker',
                             'secret',
                             'NOCHANGE',
                             'expected NOCHANGE as external_login status')

      user = User.find(:first, :attribute => 'uid', :value => 'peter.parker')
      assert !user.nil?, 'user peter.parker could not be found in Puavo'
    end

    it 'user is in expected school' do
      user = User.find(:first, :attribute => 'uid', :value => 'peter.parker')
      assert_equal extuser_target_school_dn, user.puavoSchool
    end

    it 'user has expected roles' do
      user = User.find(:first, :attribute => 'uid', :value => 'peter.parker')
      assert_equal 'student', user.puavoEduPersonAffiliation
    end

    it 'user belongs to a "heroes"-administrative group' do
      group = Group.find(:first, :attribute => 'cn', :value => 'heroes')
      assert !group.nil?, 'There is no heroes group when there should be'

      assert_equal group.puavoEduGroupType,
                   'administrative',
                   'heroes group is not an administrative group'
      assert Array(group.memberUid).include?('peter.parker'),
             'peter.parker does not belong to the "heroes"-group'
    end

    it 'user belongs to some teaching group' do
      teaching_groups = Group.find(:attribute => 'puavoEduGroupType',
                                   :value     => 'teaching group')
      is_in_a_teaching_group \
        = teaching_groups \
            && Array(teaching_groups).any? do |group|
                 Array(group.memberUid).include?('peter.parker')
               end

      assert is_in_a_teaching_group,
             'peter.parker belongs to some teaching group'
    end

    it 'user belongs to some yearclass group' do
      yearclass_groups = Group.find(:attribute => 'puavoEduGroupType',
                                    :value     => 'year class')
      is_in_a_yearclass_group \
        = yearclass_groups \
            && Array(yearclass_groups).any? do |group|
                 Array(group.memberUid).include?('peter.parker')
               end

      assert is_in_a_yearclass_group,
             'peter.parker belongs to some yearclass group'
    end
  end

  describe 'user information is updated as it should on subsequence logins' do
    before :each do
      assert_external_status('peter.parker',
                             'secret',
                             'UPDATED',
                             'expected UPDATED as external_login status')
    end


    it 'subsequent successful logins update user information when changed' do
      # change Peter Parker --> Peter Bentley and see that login fixes that
      user = User.find(:first, :attribute => 'uid', :value => 'peter.parker')
      user.surname = 'Bentley'
      user.save!

      assert_external_status('peter.parker',
                             'secret',
                             'UPDATED',
                             'expected UPDATED as external_login status')
      user = User.find(:first, :attribute => 'uid', :value => 'peter.parker')
      assert_equal 'Parker',
                   user.surname,
                   'Peter Parker is no longer Parker'
    end

    it 'subsequent successful logins update username when changed' do
      # change peter.parker --> peter.parker2 (username) and see that login
      # fixes that
      user = User.find(:first, :attribute => 'uid', :value => 'peter.parker')
      external_id = user.puavoExternalId
      user.uid = 'peter.parker2'
      user.save!

      assert_external_status('peter.parker',
                             'secret',
                             'UPDATED',
                             'login with mismatching username did not succeed')

      user = User.find(:first, :attribute => 'uid', :value => 'peter.parker')
      assert_equal 'peter.parker',
                   user.uid,
                   'peter.parker username was not changed according' \
                     + ' to external auth service'
      assert_equal external_id,
                   user.puavoExternalId,
                   'peter.parker external id has unexpectedly changed'
    end

    it 'user password is invalidated when changed and login attempted with old' do
      user = User.find(:first, :attribute => 'uid', :value => 'peter.parker')
      user.set_password 'oldpassword'     # the new is in external service
      user.save!

      assert_external_status('peter.parker',
                             'oldpassword',
                             'UPDATED_BUT_FAIL',
                             'login password not invalidated')

      msg = 'password "oldpassword" was valid,' \
              + ' even though password should have been invalidated'
      assert_password_not(user, 'oldpassword', msg)
      msg = 'password "secret" was valid,' \
              + ' even though password should have been invalidated'
      assert_password_not(user, 'secret', msg)

      assert_external_status('peter.parker',
                             'secret',
                             'UPDATED',
                             'login with correct password did not work')

      assert_password(user,
                      'secret',
                      'password "secret" was not valid,' \
                        + ' even though it should work again')
    end

    it 'user password is invalidated when old username is used and password matches' do
      user = User.find(:first, :attribute => 'uid', :value => 'peter.parker')
      user.uid = 'peter.parker2'
      user.save!

      assert_password(user, 'secret', 'password "secret" was not valid')

      assert_external_status('peter.parker2',
                             'badpassword',
                             'BADUSERCREDS',
                             'can login with a wrong Puavo username/password')

      assert_password(user, 'secret', 'password "secret" was not valid')

      assert_external_status('peter.parker2',
                             'secret',
                             'UPDATED_BUT_FAIL',
                             'can login with a wrong Puavo username')

      assert_password_not(user,
                          'secret',
                          'password "secret" should not be valid anymore' \
                            + ' (username was changed)')

      assert_external_status('peter.parker',
                             'secret',
                             'UPDATED',
                             'login with new login name failed')

      user = User.find(:first, :attribute => 'uid', :value => 'peter.parker')
      assert_password(user, 'secret', 'password "secret" was not valid')
    end

    it 'user that has been removed from external login is marked as removed' do
      # disassociate user "peter.parker" from external login service
      user = User.find(:first, :attribute => 'uid', :value => 'peter.parker')
      assert_nil user.puavoRemovalRequestTime,
                 'user removal request time is set when it should not be'
      old_external_id = user.puavoExternalId
      user.puavoExternalId = 'NEWBUTINVALID'
      user.uid = 'peter.parker2'
      user.save!

      # now we have a user does not exist in external login service

      assert_external_status('peter.parker2',
                             'secret',
                             'BADUSERCREDS',
                             'can login to user that does not exist externally')

      user = User.find(:first, :attribute => 'uid', :value => 'peter.parker2')
      assert !user.puavoRemovalRequestTime.nil?,
             'user removal request time is not set when it should be'

      # Check we can get the user back after a new login, in case the user
      # reappears in external login service.

      user.puavoExternalId = old_external_id
      user.uid = 'peter.parker'
      user.save!

      assert_external_status('peter.parker',
                             'secret',
                             'UPDATED',
                             'can not login again when scheduled for removal')

      user = User.find(:first, :attribute => 'uid', :value => 'peter.parker')
      assert_nil user.puavoRemovalRequestTime,
                 'user removal request time is set when it should not be'
    end
  end

  describe 'test group creation and membership handling' do
    it 'new groups are created as users log in' do
      group = Group.find(:first, :attribute => 'cn', :value => 'heroes')
      assert_nil group,
                  'There is a heroes group when it should not be (yet)'

      assert_external_status('peter.parker', 'secret', 'UPDATED', 'login error')

      group = Group.find(:first, :attribute => 'cn', :value => 'heroes')
      assert !group.nil?, 'There is no heroes group when there should be'

      assert_equal %w(peter.parker),
                   Array(group.memberUid),
                   'heroes group should consist of peter.parker'
    end

    it 'new members are added to groups as users log in' do
      assert_external_status('peter.parker', 'secret', 'UPDATED', 'login error')
      assert_external_status('lara.croft',   'secret', 'UPDATED', 'login error')

      group = Group.find(:first, :attribute => 'cn', :value => 'heroes')
      assert !group.nil?, 'There is no heroes group when there should be'

      assert_equal %w(peter.parker lara.croft),
                   group.memberUid,
                   'heroes group should consist of peter.parker and lara.croft'
    end

    it 'users are removed from groups according to configuration' do
      assert_external_status('peter.parker', 'secret', 'UPDATED', 'login error')
      assert_external_status('lara.croft',   'secret', 'UPDATED', 'login error')

      # remove all mappings so that peter.parker & lara.croft should
      # no longer belong to the group
      CONFIG['external_login']['example']['external_ldap']['dn_mappings'] \
            ['mappings'] = []

      assert_external_status('peter.parker', 'secret', 'UPDATED', 'login error')

      group = Group.find(:first, :attribute => 'cn', :value => 'heroes')
      assert_equal %w(lara.croft),
                   Array(group.memberUid),
                   'heroes group should consist of lara.croft only' \
                     + ' after disappearance of peter.parker'

      assert_external_status('lara.croft', 'secret', 'UPDATED', 'login error')

      group = Group.find(:first, :attribute => 'cn', :value => 'heroes')
      assert_equal [],
                   Array(group.memberUid),
                   'heroes group should not have any members'
    end
  end
end

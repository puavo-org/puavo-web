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
              'classnumber_regex'    => '^(\\d+)',
              'roles'                => [ 'student' ],
              'school_dns'           => [ extuser_target_school_dn ],
              'teaching_group_field' => 'department',
            },
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

  describe 'try login to external service with bad credentials' do
    it 'fails with unknown username' do
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

  describe 'test with good login credentials' do
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

    # XXX what about groups?

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
end

require_relative "./helper"

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
      basic_authorize 'badusername', 'badpassword'
      post '/v3/external_login/auth'
      assert_200
      parsed_response = JSON.parse(last_response.body)
      assert_equal 'BADUSERCREDS',
                   parsed_response['status'],
                   'expected BADUSERCREDS as external_login status'
    end

    it 'fails with bad password' do
      basic_authorize 'peter.parker', 'badpassword'
      post '/v3/external_login/auth'
      assert_200
      parsed_response = JSON.parse(last_response.body)
      assert_equal 'BADUSERCREDS',
                   parsed_response['status'],
                   'expected BADUSERCREDS as external_login status'

      user = User.find(:first, :attribute => 'uid', :value => 'peter.parker')
      assert_nil user, 'user peter.parker was created to Puavo, should not be'
    end
  end

  describe 'test with good login credentials' do
    before :each do
      basic_authorize 'peter.parker', 'secret'
      post '/v3/external_login/auth'
      assert_200
      @parsed_response = JSON.parse(last_response.body)
      assert_equal 'UPDATED',
                   @parsed_response['status'],
                   'expected UPDATED as external_login status'
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
      # XXX how to test password?
    end

    it 'subsequent login with bad password fails' do
      basic_authorize 'peter.parker', 'badpassword'
      post '/v3/external_login/auth'
      assert_200
      @parsed_response = JSON.parse(last_response.body)
      assert_equal 'BADUSERCREDS',
                   @parsed_response['status'],
                   'expected BADUSERCREDS as external_login status'

      user = User.find(:first, :attribute => 'uid', :value => 'peter.parker')
      assert !user.nil?, 'user peter.parker could not be found in Puavo'
    end

    it 'subsequent successful logins behave expectedly' do
      basic_authorize 'peter.parker', 'secret'
      post '/v3/external_login/auth'
      assert_200
      @parsed_response = JSON.parse(last_response.body)
      assert_equal 'NOCHANGE',
                   @parsed_response['status'],
                   'expected NOCHANGE as external_login status'

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

    it 'subsequent successful logins update user information when changed' do
      # change Peter Parker --> Peter Bentley and see that login fixes that
      user = User.find(:first, :attribute => 'uid', :value => 'peter.parker')
      user.surname = 'Bentley'
      user.save!

      basic_authorize 'peter.parker', 'secret'
      post '/v3/external_login/auth'
      assert_200
      @parsed_response = JSON.parse(last_response.body)
      assert_equal 'UPDATED',
                   @parsed_response['status'],
                   'expected UPDATED as external_login status, because surname must have changed'

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

      basic_authorize 'peter.parker', 'secret'
      post '/v3/external_login/auth'
      assert_200
      @parsed_response = JSON.parse(last_response.body)
      assert_equal 'UPDATED',
                   @parsed_response['status'],
                   'login with mismatching username did not succeed'

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

      basic_authorize 'peter.parker', 'oldpassword'
      post '/v3/external_login/auth'
      assert_200
      @parsed_response = JSON.parse(last_response.body)
      assert_equal 'UPDATED_BUT_FAIL',
                   @parsed_response['status'],
                   'login password not invalidated'

      # XXX test "oldpassword", it should not work
      # XXX test "secret", it should not work either

      basic_authorize 'peter.parker', 'secret'
      post '/v3/external_login/auth'
      assert_200
      @parsed_response = JSON.parse(last_response.body)
      assert_equal 'UPDATED',
                   @parsed_response['status'],
                   'login password not invalidated'

      # XXX test "secret", it should work again
    end

    it 'user password is invalidated when old username is used and password matches' do
      user = User.find(:first, :attribute => 'uid', :value => 'peter.parker')
      assert_nil user.puavoRemovalRequestTime,
                 'user removal request time is set when it should not be'
      user.uid = 'peter.parker2'
      user.save!

      # XXX should test password?

      basic_authorize 'peter.parker2', 'badpassword'
      post '/v3/external_login/auth'
      assert_200
      @parsed_response = JSON.parse(last_response.body)
      assert_equal 'BADUSERCREDS',
                   @parsed_response['status'],
                   'can login with a wrong Puavo username/password'

      # XXX should test password? (should still work)

      basic_authorize 'peter.parker2', 'secret'
      post '/v3/external_login/auth'
      assert_200
      @parsed_response = JSON.parse(last_response.body)
      assert_equal 'UPDATED_BUT_FAIL',
                   @parsed_response['status'],
                   'can login with a wrong Puavo username'

      # XXX should test password? (should not work)
    end

    it 'user that has been removed from external login is marked as removed' do
      # disassociate user "peter.parker" from external login service
      user = User.find(:first, :attribute => 'uid', :value => 'peter.parker')
      old_external_id = user.puavoExternalId
      user.puavoExternalId = 'NEWBUTINVALID'
      user.uid = 'peter.parker2'
      user.save!

      # now we have a user does not exist in external login service

      basic_authorize 'peter.parker2', 'secret'
      post '/v3/external_login/auth'
      assert_200
      @parsed_response = JSON.parse(last_response.body)
      assert_equal 'BADUSERCREDS',
                   @parsed_response['status'],
                   'can not login with changed Puavo username'

      user = User.find(:first, :attribute => 'uid', :value => 'peter.parker2')
      assert !user.puavoRemovalRequestTime.nil?,
             'user removal request time is not set when it should be'

      # Check we can get the user back after a new login, in case user has
      # reappears in external login service.

      user.puavoExternalId = old_external_id
      user.uid = 'peter.parker'
      user.save!

      basic_authorize 'peter.parker', 'secret'
      post '/v3/external_login/auth'
      assert_200
      @parsed_response = JSON.parse(last_response.body)
      assert_equal 'UPDATED',
                   @parsed_response['status'],
                   'can not login again when scheduled for removal'

      user = User.find(:first, :attribute => 'uid', :value => 'peter.parker')
      assert_nil user.puavoRemovalRequestTime,
                 'user removal request time is set when it should not be'
    end
  end
end

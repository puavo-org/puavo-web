require_relative "./helper"

describe PuavoRest::ExternalLogin do

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
              'school_dns'           => [ 'puavoId=5,ou=Groups,dc=edu,dc=example,dc=fi' ],
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

  it 'login to external service fails with unknown username' do
    basic_authorize 'badusername', 'badpassword'
    post '/v3/external_login/auth'
    assert_200
    response = JSON.parse(last_response.body)
    parsed_response = JSON.parse(last_response.body)
    assert_equal 'BADUSERCREDS',
                 parsed_response['status'],
                 'expected BADUSERCREDS as external_login status'

    user = User.find(:first, :attribute => 'uid', :value => 'badusername')
    assert_nil user, 'user badusername was created to Puavo, should not be'
  end

  it 'login to external service fails with bad password' do
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

  it 'login to external service succeeds with good username/password' do
    basic_authorize 'peter.parker', 'secret'
    post '/v3/external_login/auth'
    assert_200
    parsed_response = JSON.parse(last_response.body)
    assert_equal 'UPDATED',
                 parsed_response['status'],
                 'expected UPDATED as external_login status'

    user = User.find(:first, :attribute => 'uid', :value => 'peter.parker')
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
  end
end

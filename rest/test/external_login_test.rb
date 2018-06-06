require_relative "./helper"

describe PuavoRest::ExternalLogin do

  before(:each) do
    @orig_config = CONFIG.dup

    org_conf_path = '../../../config/organisations.yml'
    organisations = YAML.load_file(File.expand_path(org_conf_path, __FILE__))

    CONFIG['external_login'] = {
      'example' => {
        # XXX admin_dn is cucumber admin_dn, but how to get it nicely
        # XXX so it is always correct?
        'admin_dn'       => 'puavoId=8,ou=People,dc=edu,dc=example,dc=fi',
        'admin_password' => organisations['example']['owner_pw'],
        'service'        => 'external_ldap',
#        'dn_mappings'    => {
#          'defaults' => {
#            'classnumber_regex'    => '^(\\d+)',
#            'teaching_group_field' => 'department',
#          },
#          'mappings' => [
#          ],
#        },
        'external_ldap'  => {
          'base'              => 'dc=edu,dc=heroes,dc=fi',
          'bind_dn'           => organisations['heroes']['owner'],
          'bind_password'     => organisations['heroes']['owner_pw'],
          'external_id_field' => 'mail',
          'server'            => 'localhost',
        }
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
    assert_equal 401, last_response.status, "Body: #{ last_response.body }"

    # XXX should check that peter.parker does *not* exist in
    # XXX example-organisation
  end

  it 'login to external service fails with bad password' do
    basic_authorize 'peter.parker', 'badpassword'
    post '/v3/external_login/auth'
    assert_equal 401, last_response.status, "Body: #{ last_response.body }"

    # XXX should check that peter.parker does *not* exist in
    # XXX example-organisation
  end

  it 'login to external service succeeds with good username/password' do
    basic_authorize 'peter.parker', 'secret'
    post '/v3/external_login/auth'
    assert_200

    # XXX should check that peter.parker *does* exist in example-organisation
    # XXX and it has the correct attributes
    # XXX    :external_id               = peter.parker@example.com
    # XXX    :givenName                 = Peter
    # XXX ?? :mail                      = peter.parker@example.com
    # XXX ?? :preferredLanguage         = fi
    # XXX ?? :puavoEduPersonAffiliation = admin
    # XXX    :sn                        = Parker
    # XXX    :uid                       = peter.parker

    # XXX what about groups, what should be tested?
  end

  it 'login to external service succeeds with another good username/password' do
    basic_authorize 'lara.croft', 'secret'
    post '/v3/external_login/auth'
    assert_200

    # XXX should check that peter.parker *does* exist in example-organisation
    # XXX and it has the correct attributes
    # XXX    :external_id               = peter.parker@example.com
    # XXX    :givenName                 = Peter
    # XXX ?? :mail                      = peter.parker@example.com
    # XXX ?? :preferredLanguage         = fi
    # XXX ?? :puavoEduPersonAffiliation = admin
    # XXX    :sn                        = Parker
    # XXX    :uid                       = peter.parker

    # XXX what about groups, what should be tested?

  end

  it 'user groups for peter.parker are correct' do
    # XXX
  end

  it 'user groups for lara.croft are correct' do
    # XXX
  end
end

require_relative "./helper"

describe PuavoRest::ExternalLogin do

  before(:each) do
    @orig_config = CONFIG.dup

    org_conf_path = '../../../config/organisations.yml'
    organisations = YAML.load_file(File.expand_path(org_conf_path, __FILE__))

    CONFIG['external_login'] = {
      'hogwarts' => {
        'admin_dn'       => PUAVO_ETC.ldap_dn,
        'admin_password' => PUAVO_ETC.ldap_password,
        'service'        => 'external_ldap',
        'external_ldap'  => {
          'base'          => 'dc=edu,dc=heroes,dc=fi',
          'bind_dn'       => organisations['heroes']['owner'],
          'bind_password' => organisations['heroes']['owner_pw'],
          'port'          => '636',
          'server'        => 'localhost',
        }
      }
    }

    Puavo::Test.clean_up_ldap

#   default_domain = CONFIG["default_organisation_domain"]
#   domain_first, *domain_the_rest = default_domain.split('.')
#   heroes_domain = [ 'heroes', *domain_the_rest ].join('.')

    heroes_org = Puavo::Organisation.find('heroes')
    default_ldap_configuration = ActiveLdap::Base.ensure_configuration
    LdapBase.ldap_setup_connection(
      heroes_org.ldap_host,
      heroes_org.ldap_base,
      'XXX', # XXX where to get this from?
      organisations['heroes']['owner_pw'],
    )
 
    # puts "dn=#{ organisations['heroes']['owner'] }"
    # puts "password=#{ organisations['heroes']['owner_pw'] }"
#   LdapModel.setup(
#     :credentials => {
        # :dn       => organisations['heroes']['owner'],
        # XXX where to get this dn?
#       :dn       => 'XXX'
#       :password => organisations['heroes']['owner_pw'],
#     },
#     :organisation => PuavoRest::Organisation.by_domain!(heroes_domain),
#   )

    # User.all
    ext_school = School.find(:first, :attribute => 'name', :value => 'Uagadou')
    puts "this is ext_school: #{ ext_school.inspect }"
    # ext_school.destroy if ext_school
    exit 0

    @ext_school = PuavoRest::School.new(
      :abbreviation => 'uagadou',
      :name         => 'Uagadou',
    )
    @ext_school.save!

    @ext_group = PuavoRest::Group.new(
      :abbreviation => 'extgroup1',
      :name         => 'External Group 1',
      :school_dn    => @ext_school.dn,
      :type         => 'teaching group',
    )
    @ext_group.save!

    @ext_user1_uid = 'babajide.akingbade'
    @ext_user1_password = 'password.akingbade'

    @ext_user1 = PuavoRest::User.new(
      :first_name => 'Babajide',
      :last_name  => 'Akingbade',
      :password   => @ext_user1_password,
      :roles      => [ 'student' ],
      :school_dns => [ @ext_school.dn.to_s ],
      :username   => 'babajide.akingbade',
    )
    @ext_user1.save!

#   @our_school = PuavoRest::School.create(
#     :cn          => 'gryffindor',
#     :displayName => 'Gryffindor',
#   )
#   @our_school.save!
  end

  after do
    CONFIG = @orig_config
  end

  it 'login to external service fails with unknown username' do
    return
    post '/v3/external_login', {
      'username' => 'badusername',
      'password' => 'badpassword',
    }
    assert_equal 401, last_response.status, "Body: #{ last_response.body }"
  end

  it 'login to external service fails with bad password' do
    return
    post '/v3/external_login', {
      'username' => @ext_user1_uid,
      'password' => 'badpassword',
    }
    assert_equal 401, last_response.status, "Body: #{ last_response.body }"
  end

  it 'login to external service succeeds with good username/password' do
    return
    post '/v3/external_login', {
      'username' => @ext_user1_uid,
      'password' => @ext_user1_password,
    }
    assert_200
  end
end

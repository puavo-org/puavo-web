require 'net/ldap'
require 'openssl'
require 'puavo/etc'
require 'yaml'

module PuavoRest
  module ExternalLoginTestConfig
    def self.get_dn_from_cn(ldap_base, cn)
      ldap = Net::LDAP.new :base => ldap_base,
                           :host => 'localhost',
                           :auth => {
                             :method   => :simple,
                             :username => PUAVO_ETC.ldap_dn,
                             :password => PUAVO_ETC.ldap_password,
                           },
                           :encryption => {
                             :method => :start_tls,
                             :tls_options => {
                               :verify_mode => OpenSSL::SSL::VERIFY_NONE,
                             }
                           }

      entries = ldap.search(:filter => Net::LDAP::Filter.eq('cn', cn))
      raise "could not find entry #{ cn } from #{ ldap_base }" \
        unless entries && entries.count == 1

      entries.first.dn.to_s
    end

    def self.resistance_administrative_group(role)
      {
        'add_administrative_group' => {
          'displayname' => 'Resistence',
          'name'        => 'resistence', },
        'add_roles' => [ role ],
      }
    end

    def self.get_configuration
      admin_dn   = get_dn_from_cn('dc=edu,dc=external,dc=net', 'cucumber')
      bind_dn    = get_dn_from_cn('dc=edu,dc=heroes,dc=net', 'admin')
      indiana_dn = get_dn_from_cn('dc=edu,dc=heroes,dc=net', 'indiana.jones')
      lara_dn    = get_dn_from_cn('dc=edu,dc=heroes,dc=net', 'lara.croft')
      sarah_dn   = get_dn_from_cn('dc=edu,dc=heroes,dc=net', 'sarah.connor')
      thomas_dn  = get_dn_from_cn('dc=edu,dc=heroes,dc=net', 'thomas.anderson')

      target_school_dn = get_dn_from_cn('dc=edu,dc=external,dc=net',
                                        'administration')

      organisations = YAML.load_file('/etc/puavo-web/organisations.yml')

      {
        'external' => {
          'admin_dn'          => admin_dn,
          'admin_password'    => organisations['external']['owner_pw'],
          'manage_puavousers' => true,
          'service'           => 'external_ldap',
          'external_ldap'     => {
            'authentication_method'   => 'user_credentials',
            'base'                    => 'dc=edu,dc=heroes,dc=net',
            'bind_dn'                 => bind_dn,
            'bind_password'           => organisations['heroes']['owner_pw'],
            'encryption_method'       => 'start_tls',
            'user_mappings' => {
              'defaults' => {
                'classnumber_regex'    => '(\\d)$',    # typically: '^(\\d+)'
                'roles'                => [ 'student' ],
                'school_dns'           => [ target_school_dn ],
                'teaching_group_field' => 'gidNumber', # typically: 'department'
                'teaching_group_regex' => '^(.*)$',
              },
              'by_dn' => [
                { '*,ou=People,dc=edu,dc=heroes,dc=net' => [
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
                { indiana_dn => [ resistance_administrative_group('teacher') ]},
                { lara_dn    => [ resistance_administrative_group('admin'  ) ]},
                { sarah_dn   => [ resistance_administrative_group('teacher') ]},
                { thomas_dn  => [ resistance_administrative_group('admin'  ) ]},
              ],
            },
            'external_id_field'       => 'eduPersonPrincipalName',
            'external_username_field' => 'mail',
            'password_change' => { 'api' => 'openldap', },
            'server' => 'localhost',
            'subtrees' => [ 'ou=People,dc=edu,dc=heroes,dc=net' ],
          },
        }
      }
    end
  end
end

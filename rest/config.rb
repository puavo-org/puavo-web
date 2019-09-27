require "socket"
require "yaml"
require "puavo/etc"


fqdn = Socket.gethostbyname(Socket.gethostname).first

default_config = {
  "ldap" => fqdn,
  "ldapmaster" => PUAVO_ETC.get(:ldap_master),
  "topdomain" => PUAVO_ETC.get(:topdomain),
  "ltsp_server_data_dir" => "/run/puavo-rest",
  "fqdn" => fqdn,
  "keytab" => "/etc/puavo/puavo-rest.keytab",
  "default_organisation_domain" => PUAVO_ETC.get(:domain),
  "bootserver" => true,
  "redis" => {
    :db => 0
  },
  "server" => {
    :dn => PUAVO_ETC.ldap_dn,
    :password => PUAVO_ETC.ldap_password
  }
}

def get_dn_from_cn(ldap_base, cn)
  require 'net/ldap'
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

def resistance_administrative_group(role)
  {
    'add_administrative_group' => {
      'displayname' => 'Resistence',
      'name'        => 'resistence', },
    'add_roles' => [ role ],
  }
end

def get_external_login_test_configuration
  admin_dn   = get_dn_from_cn('dc=edu,dc=example,dc=fi', 'cucumber')
  bind_dn    = get_dn_from_cn('dc=edu,dc=heroes,dc=fi',  'admin')
  indiana_dn = get_dn_from_cn('dc=edu,dc=heroes,dc=fi',  'indiana.jones')
  lara_dn    = get_dn_from_cn('dc=edu,dc=heroes,dc=fi',  'lara.croft')
  sarah_dn   = get_dn_from_cn('dc=edu,dc=heroes,dc=fi',  'sarah.connor')
  thomas_dn  = get_dn_from_cn('dc=edu,dc=heroes,dc=fi',  'thomas.anderson')

  target_school_dn = get_dn_from_cn('dc=edu,dc=example,dc=fi', 'administration')

  organisations = YAML.load_file('/etc/puavo-web/organisations.yml')

  {
    'example' => {
      'admin_dn'       => admin_dn,
      'admin_password' => organisations['example']['owner_pw'],
      'service'        => 'external_ldap',
      'external_ldap'  => {
        'base'                    => 'dc=edu,dc=heroes,dc=fi',
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
        'subtrees' => [ 'ou=People,dc=edu,dc=heroes,dc=fi' ],
      },
    }
  }

end

if ENV['RACK_ENV'] == 'test' then
  CONFIG = {
    "ldap" => fqdn,
    "ldapmaster" => PUAVO_ETC.get(:ldap_master),
    "topdomain" => "opinsys.net",
    "ltsp_server_data_dir" => "/tmp/puavo-rest-test",
    "default_organisation_domain" => "example.opinsys.net",
    "bootserver" => true,
    "cloud" => true,
    "password_management" => {
      "secret" => "foobar",
      "smtp" => {
        "from" => "Opinsys <no-reply@opinsys.fi>",
        "via_options" => {
          "address" => "localhost",
          "port" => 25,
          "enable_starttls_auto" => false
        }
      }
    },
    "email_confirm" => {
      "secret" => "barfoo" },
    "redis" => {
      :db => 1
    },
    "server" => {
      :dn => PUAVO_ETC.ldap_dn,
      :password => PUAVO_ETC.ldap_password
    },
    "puavo_ca" => "http://localhost:8080",

    'external_login' => get_external_login_test_configuration(),
  }
else
  customizations = [
    "/etc/puavo-rest.yml",
    "/etc/puavo-rest.d/external_logins.yml",
    "./puavo-rest.yml",
  ].map do |path|
    begin
      YAML.load_file path
    rescue Errno::ENOENT
      {}
    end
  end.reduce({}) do |memo, config|
    memo.merge(config)
  end

  # If we are running in production mode, but with the intent of running
  # the puavo-web cucumber tests, we merge the external login
  # configurations for testing purposes.  Note that for this to work
  # puavo-rest must be on the same server as puavo-web, because it looks up
  # the configuration file "/etc/puavo-web/organisations.yml".
  if ENV['PUAVO_WEB_CUCUMBER_TESTS'] == 'true' then
    customizations.merge!({
      'external_login' => get_external_login_test_configuration(),
    })
  end

  CONFIG = default_config.merge(customizations)
end

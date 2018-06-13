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

if ENV["RACK_ENV"] == "test"
  # XXX how to know this is the "cucumber"-user dn?
  cucumber_user_dn = 'puavoId=8,ou=People,dc=edu,dc=example,dc=fi'

  org_conf_path = '../../config/organisations.yml'
  organisations = YAML.load_file(File.expand_path(org_conf_path, __FILE__))

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

    'external_login' => {
      'example' => {
        'admin_dn'       => cucumber_user_dn,
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
              'classnumber_regex'    => '(\\d)$',    # typically: '^(\\d+)'
              'roles'                => [ 'student' ],
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

  CONFIG = default_config.merge(customizations)
end

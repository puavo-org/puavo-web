require "socket"
require "yaml"
require "puavo/etc"


fqdn = Socket.gethostbyname(Socket.gethostname).first

default_config = {
  "ldap" => fqdn,
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
  CONFIG = {
    "ldap" => fqdn,
    "topdomain" => "example.net",
    "ltsp_server_data_dir" => "/tmp/puavo-rest-test",
    "default_organisation_domain" => "www.example.net",
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
    }
  }
else

  customizations = [
    "/etc/puavo-rest.yml",
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

require "socket"
require "yaml"
require "puavo/etc"
require 'openssl'


fqdn = Addrinfo.getaddrinfo(Socket.gethostname, nil).first.getnameinfo.first

default_config = {
  "ldap" => fqdn,
  "ldapmaster" => PUAVO_ETC.get(:ldap_master),
  "topdomain" => PUAVO_ETC.get(:topdomain),
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


if ENV['RACK_ENV'] == 'test' then
  # XXX For testing system we use a strange configuration, where
  # XXX puavo-rest is simultaneously a bootserver and a cloud server.
  # XXX Here, PUAVO_ETC.ldap_dn == "uid=admin,o=puavo" that is not in
  # XXX production anywhere, not in bootservers or in the cloud
  # XXX (bootservers use their own credentials and the cloud server uses
  # XXX "uid=puavo,o=puavo").  This means that, by design, some tests in
  # XXX the test system may return results which do not match what actually
  # XXX happens in production systems, mostly regarding ldap ACLs
  # XXX with the ldap accounts that puavo-rest uses.

  CONFIG = {
    "ldap" => fqdn,
    "ldapmaster" => PUAVO_ETC.get(:ldap_master),
    "topdomain" => "puavo.net",
    "default_organisation_domain" => "example.puavo.net",
    "bootserver" => true,
    "cloud" => true,
    "password_management" => {
      "secret" => "foobar",
      "lifetime" => 3600,
      "ip_whitelist" => ['127.0.0.1'],
      "smtp" => {
        "from" => "Puavo Org <no-reply@puavo.net>",
        "via_options" => {
          "address" => "localhost",
          "port" => 25,
          "enable_starttls_auto" => false
        }
      }
    },
    "email_management" => {
      "ip_whitelist" => ['127.0.0.1'],
      "smtp" => {
        "from" => "Puavo Org <no-reply@puavo.net>",
        "via_options" => {
          "address" => "localhost",
          "port" => 25,
          "enable_starttls_auto" => false
        }
      }
    },
    'mfa_server' => {
      'server' => 'http://127.0.0.1:9999',
      'bearer_key' => 'devel'
    },
    'mfa_management' => {
      'ip_whitelist' => ['127.0.0.1'],
      'client' => {
        'username' => 'mfa_user',
        'password' => 'mfa_password'
      },
      'server' => {
        'username' => 'uid=mfa-mgmt,o=puavo',
        'password' => 'password'
      },
    },
    'oauth2' => {
      'key_files' => {
        'private_pem' => '/etc/puavo-rest.d/oauth2_token_signing_private_key_example.pem',
        'public_pem' => '/etc/puavo-rest.d/oauth2_token_signing_public_key_example.pem',
        'public_jwks' => '/etc/puavo-rest.d/oauth2_public_jwks_example.json',
      },
      'kid' => 'puavo_standalone_20250115T095034Z',   # change this if the PEM files are rotated
      'client_database' => {
        'host' => '127.0.0.1',
        'port' => 5432,
        'database' => 'oauth2',
        'user' => 'standalone_user',
        'password' => 'standalone_password'
      },
      'ldap_id' => {
        'userinfo' => {       # The built-in ID that's used in the userinfo endpoint. Do not delete!
          'dn' => PUAVO_ETC.ldap_dn,
          'password' => PUAVO_ETC.ldap_password
        },
        'admin' => {
          'dn' => 'uid=admin,o=puavo',
          'password' => 'password'
        },
      },
      'audit' => {
        'enabled' => false,
        'ip_logging' => false,
      }
    },
    "redis" => {
      :db => 1
    },
    "server" => {
      :dn => PUAVO_ETC.ldap_dn,
      :password => PUAVO_ETC.ldap_password
    },
    "puavo_ca" => "http://localhost:8080",
    'branding' => {
      'copyright' => '© Opinsys',
      'copyright_year' => '2025',
      'copyright_with_year' => '© Opinsys Oy 2025',
      'manufacturer' => {
        'generic_name' => 'Opinsys',
        'url' => 'https://opinsys.fi',
        'logo' => '/v3/login/opinsys_logo.svg',
        'alt_text' => 'Opinsys Oy logo',
        'title' => 'Opinsys Oy',
        'logo_width' => 150,
        'logo_height' => 34,
        'technical_support_email' => 'support@hogwarts.puavo.net',
        'technical_support_phone' => {
          'short' => '1234567890',
          'international' => '+358 1234567890',
        },
      }
    },
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

  # If we are running in production mode, but with the intent of running
  # the puavo-web cucumber tests, we merge the external login
  # configurations for testing purposes.  Note that for this to work
  # puavo-rest must be on the same server as puavo-web, because it looks up
  # the configuration file "/etc/puavo-web/organisations.yml".
  if ENV['PUAVO_WEB_CUCUMBER_TESTS'] == 'true' then
    require_relative './lib/external_login_test_config'
    CONFIG.merge!({
      'external_login' =>
        PuavoRest::ExternalLoginTestConfig::get_configuration(),
    })

    # Make profile editor tests work. This minimal configuration is enough for now, because we
    # don't actually send any verification messages yet. We only need to make the email management
    # authentication work, and give the email management controller a minimal whitelist to pass
    # the sender check. If we one day start testing verification email sending, then this part
    # needs to be expanded.
    CONFIG.merge!({
      'email_management' => {
        'ip_whitelist' => ['127.0.0.1'],
      }
    })
  end
end

# Load the public OAuth2 JWT validation key. The private key file is loaded only when
# signing an access token, so that its contents cannot leak through global variables.
public_key = nil

if CONFIG.fetch('oauth2', {}).fetch('key_files', {}).include?('public_pem')
  begin
    public_key = OpenSSL::PKey.read(File.read(CONFIG['oauth2']['key_files']['public_pem']))
  rescue StandardError => e
    puts "ERROR: Cannot load the OAuth2 JWT validation key: #{e}"
    puts "ERROR: OAuth2 access token validations will always fail and access tokens cannot be used"
    public_key = nil
  end
end

OAUTH2_TOKEN_VERIFICATION_PUBLIC_KEY = public_key.freeze

# Load organisations.yml if it exists
begin
  ORGANISATIONS = YAML.load_file('/etc/puavo-web/organisations.yml').freeze
rescue StandardError => e
  ORGANISATIONS = {}.freeze
end

def get_automatic_email(organisation_name)
  conf = ORGANISATIONS.fetch(organisation_name, {}).fetch('automatic_email_addresses', {})
  return [conf.fetch('enabled', false), conf.fetch('domain', nil)]
end

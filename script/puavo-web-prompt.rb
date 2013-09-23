#!/usr/bin/ruby1.9.1

require "pry"
require "io/console"
require "puavo/etc"

def ask(question, opts={})
  new_value = nil
  while true
    print "#{question} [#{ opts[:default] }]"
    print "(optional)" if opts[:optional]
    print "> "
    new_value = STDIN.gets.strip

    # Use default or previous value if user did not give anything
    new_value =  opts[:default] if new_value.to_s.empty?

    # Break if we have value
    break if not new_value.to_s.empty?

    # Allow empty value in optional
    break if opts[:optional]
  end
  new_value
end

def puavo_configuration
  ActiveLdap::Base.ensure_configuration
end
def ldap_host
  puavo_configuration["host"]
end

@credentials = {}
@credentials[:organisation_key] = ask("Organisation key", :default => "hogwarts")

uid_or_dn = ask("Username/DN", :default => "uid=admin,o=puavo")

begin
  @credentials[:dn] = ActiveLdap::DistinguishedName.parse uid_or_dn
rescue ActiveLdap::DistinguishedNameInvalid
  @credentials[:uid] = uid_or_dn
end

STDIN.noecho do
  @credentials[:password] = ask("Password", :default => PUAVO_ETC.get(:ldap_password))
end

@authentication = Puavo::Authentication.new
@authentication.configure_ldap_connection(@credentials)
@authentication.authenticate

# Manually configure ExternalService because Puavo::Authentication configures
# read-only access to it with o=Puavo
ExternalService.ldap_setup_connection(
  @authentication.ldap_host,
  @authentication.puavo_configuration["base"],
  @authentication.dn,
  @credentials[:password]
)

binding.pry

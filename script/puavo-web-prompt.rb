#!/usr/bin/ruby1.9.1

require "pry"
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

# ExternalService is on o=puavo database. So use always uid=puavo for it.
ExternalService.ldap_setup_connection(
  ldap_host,
  puavo_configuration["base"],
  puavo_configuration["bind_dn"],
  puavo_configuration["password"]
)

puts "LdapBase connection:"
LdapBase.ldap_setup_connection(
  ask("ldap host", :default => ldap_host),
  puavo_configuration["base"],
  ask("dn", :default => puavo_configuration["bind_dn"]),
  ask("password", :default => puavo_configuration["password"])
)


binding.pry

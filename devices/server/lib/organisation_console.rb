

def init_org(organisation_key)

  unless organisation = Puavo::Organisation.find(organisation_key.to_s)
    puts "Can't find organisation from configuration file (config/organisation.yml)."
    return
  end

  I18n.locale = organisation.value_by_key('locale')

  puts "Organisation: " + organisation.name.to_s

  print "Username: "
  username = STDIN.gets.chomp
  print "Password: "
  system('stty','-echo');
  admin_password = STDIN.gets.chomp
  system('stty','echo');

  default_ldap_configuration = ActiveLdap::Base.ensure_configuration
  puavo_dn = default_ldap_configuration["bind_dn"]
  puavo_password = default_ldap_configuration["password"]# Setting up ldap configuration

  LdapBase.ldap_setup_connection( organisation.ldap_host,
                                  organisation.ldap_base,
                                  puavo_dn,
                                  puavo_password )

  admin_user = User.find(:first, :attribute => "uid", :value => username)

  LdapBase.ldap_setup_connection( organisation.ldap_host,
                                  organisation.ldap_base,
                                  admin_user.dn.to_s,
                                  admin_password )
end

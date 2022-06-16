#!/usr/bin/ruby
#
# Remove an owner user from all organisations.
#
#  bundle exec rails runner script/puavo-add-owner.rb
#

require 'highline'

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

# No options here
def ask_password(question)
  cli = HighLine.new
  return cli.ask(question) { |q| q.echo = "*" }
end

ldap_admin_dn = ask("LDAP admin DN", :default => "uid=admin,o=puavo")
ldap_admin_password = ask_password("LDAP admin password: ")

ldap_configuration = ActiveLdap::Base.ensure_configuration.merge(
  { "host" => PUAVO_ETC.ldap_master,
    "base" => "",
    "bind_dn" => ldap_admin_dn,
    "password" => ldap_admin_password } )

ActiveLdap::Base.setup_connection( ldap_configuration )


databases =  ActiveLdap::Base.search( :filter => "(objectClass=*)",
                                      :scope => :base,
                                      :attributes => ["namingContexts"] )[0][1]["namingContexts"]


owner_uid = ask("Remove following owner user:")

databases.each_with_index do |database, index|
  # Skip o=puavo database
  next if database == "o=puavo"

  if Puavo::CONFIG["puavo_add_owner_skip_organisations"].to_a.include?(database)
    next
  end

  ActiveLdap::Base.active_connections.keys.each do |connection_name|
    ActiveLdap::Base.remove_connection(connection_name)
  end

  new_configuration = LdapBase.ensure_configuration.merge( {
    "host" => PUAVO_ETC.ldap_master,
    "base" => database,
    "bind_dn" => ldap_admin_dn,
    "password" => ldap_admin_password  } )

  LdapBase.setup_connection( new_configuration )

  puts "(#{index+1}/#{databases.count}) #{database}"

  if user = User.find(:first, :attribute => "uid", :value => owner_uid )
    begin
      user.destroy
    rescue => e
      puts "  ERROR: #{e}"
    end
  else
    puts "  Can't find the user"
    next
  end
end

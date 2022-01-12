#!/usr/bin/ruby
#
# Create a new owner user to all organisations. If the user already exists,
# their password will be updated.
#
#  bundle exec rails runner script/puavo-add-owner.rb
#

require 'io/console'
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

def read_char
  STDIN.echo = false
  STDIN.raw!
  input = STDIN.getc.chr
  if input == "\e"
    input << STDIN.read_nonblock(3) rescue nil
    input << STDIN.read_nonblock(2) rescue nil
  end
ensure
  STDIN.echo = true
  STDIN.cooked!
  return input
end

def try_save_user(user)
  while(true)
    begin
      user.save!
      break
    rescue Exception => e
      puts "Can't save user: #{e.to_s}"
      puts "Press S to skip this organisation, Esc to abort, or any other key to retry..."

      c = read_char
      break if 'sS'.include?(c)
      raise Interrupt if c.chr == "\u001b"
    end
  end
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


owner_uid = ask("Username for new owner user:")
owner_password = ask_password("New password: ")
owner_password_confirm = ask_password("New password confirmation: ")

if owner_password != owner_password_confirm
  puts "Passwords don't match, aborted!"
  exit
end

owner_given_name = ask("Given name: ")
owner_surname = ask("Surname: ")
owner_ssh_public_key = ask("Public key: ")

if databases.nil? || databases.empty?
  puts "No databases found! Did you enter the correct LDAP credentials?"
  exit
end

databases.each_with_index do |database, index|
  # Skip o=puavo database
  next if database == "o=puavo"
  next if Puavo::Organisation.all.values.select{ |o| o["ldap_base"] == database }.empty?

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

  begin
    if user = User.find(:first, :attribute => "uid", :value => owner_uid )
      puts "  User already exists, updating account information"
    else
      puts "  Creating new user"
      school = School.find(:first, :attribute => "displayName", :value => "Administration")
      user = User.new
      user.uid = owner_uid
      user.puavoSchool = school.dn
      user.puavoEduPersonPrimarySchool = school.dn
    end

    user.givenName = owner_given_name
    user.sn = owner_surname
    user.new_password = owner_password
    user.new_password_confirmation = owner_password
    user.password_change_mode = :no_upstream
    user.puavoEduPersonAffiliation = "admin"
    user.puavoSshPublicKey = owner_ssh_public_key
    try_save_user(user)

    begin
      ldap_organisation = LdapOrganisation.first
      ldap_organisation.ldap_modify_operation( :add, [{ "owner" => [user.dn.to_s] }] )
      puts "  User is now an organisation owner"
    rescue ActiveLdap::LdapError::TypeOrValueExists
      puts "  User is already an organisation owner"
    end
  rescue => e
    puts "  ERROR: #{e}"
  end
end

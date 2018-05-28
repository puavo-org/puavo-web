#!/usr/bin/ruby

# Purges an organisation of it's data

COLOR_RED = "\033[0;31m"
COLOR_YELLOW = "\033[1;33m"
COLOR_GREEN = "\033[1;32m"
COLOR_NONE = "\033[0m"

if ARGV.length < 1
  puts "#{COLOR_YELLOW}"
  puts "This script deletes all data from an organisation. You don't want to do this."
  puts "Turn back now."
  puts "Usage: #{__FILE__} <organisation name>"
  puts "#{COLOR_NONE}"
  exit 1
end

organisation_name = ARGV[0]

require 'io/console'
require "puavo/etc"

def read_string(prompt, password=false)
  s = nil

  loop do
    begin
      print prompt
      if password
        s = STDIN.noecho(&:gets).chomp
      else
        s = STDIN.gets.chomp
      end
    rescue Interrupt
      return nil
    end

    return s #if !s.nil? && !s.empty?
  end
end

puts ''
puts "#{COLOR_YELLOW}This script cleans an organisation in Puavo. It will #{COLOR_RED}DELETE
all groups, roles, devices, schools, users, LDAP services,
external files and much more#{COLOR_YELLOW}. It spares only the Administration
school and the admin users in it.#{COLOR_NONE} The only way to undo this is
to restore from backups. You have those, right?"

puts COLOR_RED
puts '*' * 50
puts ''
puts "You're about to clean the \"#{organisation_name}\" organisation."
puts ''
puts '*' * 50
puts COLOR_YELLOW
puts 'Is this what you intended when you ran this script?'
puts COLOR_NONE
puts 'Type "YES" to continue. Any other input will exit.'

answer = read_string('> ')

unless answer == "YES"
  puts "#{COLOR_GREEN}That wasn't what I asked for! Exiting.#{COLOR_NONE}"
  puts ''
  exit 1
end

puts "#{COLOR_YELLOW}Okay then...#{COLOR_NONE}"
puts ''

if ARGV.length >= 1 && ARGV[1] != '-IReallyMeanIt'
  puts 'Of course, you also need to say -IReallyMeanIt after the organisation'
  puts 'name to actually do something. Exiting.'
  puts ''
  exit 1
end

puts 'Authenticate yourself, mortal:'

uid_or_dn = read_string('Username or DN: ')

if uid_or_dn.nil? || uid_or_dn.empty?
  puts "#{COLOR_GREEN}Good choice, exiting#{COLOR_NONE}"
  puts ''
  exit 1
end

password = read_string('Password (will not echo): ', true)

if password.nil? || password.empty?
  puts "#{COLOR_GREEN}Good choice, exiting#{COLOR_NONE}"
  puts ''
  exit 1
end

@credentials = {}
@credentials[:organisation_key] = organisation_name

begin
  @credentials[:dn] = ActiveLdap::DistinguishedName.parse uid_or_dn
rescue ActiveLdap::DistinguishedNameInvalid
  @credentials[:uid] = uid_or_dn
end

@credentials[:password] = password

begin
  @authentication = Puavo::Authentication.new
  @authentication.configure_ldap_connection(@credentials)
  @authentication.authenticate

  # Manually configure ExternalService because Puavo::Authentication configures
  # read-only access to it with o=Puavo
  ExternalService.ldap_setup_connection(
    @authentication.ldap_host,
    @authentication.puavo_configuration['base'],
    @authentication.dn,
    @credentials[:password]
  )
rescue StandardError => e
  puts ''
  puts "#{COLOR_RED}Those credentials didn't work:#{COLOR_NONE}"
  puts e
  puts "#{COLOR_RED}Stopping here.#{COLOR_NONE}"
  puts ''
  exit 1
end

puts ''
puts "#{COLOR_YELLOW}Those credentials appear to work.#{COLOR_NONE}"
puts ''
puts 'One more question...'

puts COLOR_RED
puts '*' * 50
puts "YOU ARE ABOUT TO EFFECTIVELY DESTROY THE \"#{organisation_name}\" ORGANISATION!"
puts 'IS THIS REALLY WHAT YOU WANTED?'
puts '*' * 50
puts COLOR_NONE

expected = ([*('A'..'Z'),*('a'..'z'),*('0'..'9')]).sample(8).join

puts 'Please type the following password exactly as printed to confirm your degenerate intentions:'
puts "#{expected}"
puts ''

answer = read_string('> ')

if answer != expected
  puts "#{COLOR_GREEN}The strings don't match, exiting. That was a really close one!#{COLOR_NONE}"
  puts ''
  exit 1
end

puts ''
puts "#{COLOR_YELLOW}Very well then. Witness the destruction of the \"#{organisation_name}\" organisation below."
puts "#{COLOR_GREEN}Ctrl+C will stop this, but you will always lose something...#{COLOR_NONE}"
puts ''

# Find the administration school
admin_school = School.all.each.reject { |s| s.cn != 'administration' }.first

if admin_school.nil?
  puts "ERROR: Cannot find the 'Administration' school. Stopping here."
  quit
end

o = LdapOrganisation.current
modified = false

unless o.puavoWlanSSID.nil?
  puts 'Clearing organisation WLANs'
  o.puavoWlanSSID = []
  modified = true
end

if o.puavoRemoteDesktopPrivateKey
  puts 'Clearing organisation remote desktop private key'
  o.puavoRemoteDesktopPrivateKey = ''
  modified = true
end

if o.puavoRemoteDesktopPublicKey
  puts 'Clearing organisation remote desktop public key'
  o.puavoRemoteDesktopPublicKey = ''
  modified = true
end

if o.puavoBillingInfo
  puts "Clearing organisation billing info"
  o.puavoBillingInfo = nil
  modified = true
end

if o.puavoConf
  puts "Clearing organisation PuavoConf variables"
  o.puavoConf = nil
  modified = true
end

if modified
  begin
    o.save!
  rescue StandardError => e
    puts "Could not save organisation data: #{e}"
  end
end

owners = o.owner.each.select { |dn| dn != 'uid=admin,o=puavo' }

# Remove all users except admins in the administration school.
# Also clean up organisation owners.
User.all.each do |u|
  next if u.puavoEduPersonAffiliation == 'admin' && u.puavoSchool == admin_school.dn

  if !owners.nil? && owners.include?(u.dn)
    puts "Removing organisation ownership from user '#{u.displayName}''"
    LdapOrganisation.current.remove_owner(u)
  end

  puts "Deleting user '#{u.displayName}'"

  begin
    u.delete
  rescue StandardError => e
    puts "  -> Failed: #{e}"
  end
end

# None of these matter anymore
Group.all.each do |i|
  puts "Deleting group '#{i.cn}'"

  begin
    i.delete
  rescue StandardError => e
    puts "  -> Failed: #{e}"
  end
end

Role.all.each do |i|
  puts "Deleting role '#{i.cn}'"

  begin
    i.delete
  rescue StandardError => e
    puts "  -> Failed: #{e}"
  end
end

Device.all.each do |i|
  puts "Deleting device '#{i.cn}'"

  begin
    i.delete
  rescue StandardError => e
    puts "  -> Failed: #{e}"
  end
end

Server.all.each do |i|
  puts "Deleting server '#{i.cn}'"

  begin
    i.delete
  rescue StandardError => e
    puts "  -> Failed: #{e}"
  end
end

Printer.all.each do |i|
  puts "Deleting printer '#{i.dn}'"

  begin
    i.delete
  rescue StandardError => e
    puts "  -> Failed: #{e}"
  end
end

# Delete all non-administration schools
School.all.each do |s|
  if s.dn == admin_school.dn
    unless s.puavoWlanSSID.nil?
      puts "Clearing administration school WLANs"
      s.puavoWlanSSID = []

      begin
        s.save!
      rescue StandardError => e
        puts "  -> Failed: #{e}"
      end
    end
  else
    puts "Deleting school '#{s.displayName}'"

    begin
      s.delete
    rescue StandardError => e
      puts "  -> Failed: #{e}"
    end
  end
end

puts ''
puts "#{COLOR_YELLOW}All done. I hope you're happy now.#{COLOR_NONE}"
puts ''

exit 0

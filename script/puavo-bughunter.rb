#!/usr/bin/ruby

require "pry"
require "io/console"
require "puavo/etc"

#require 'byebug'

@credentials = {}

if ARGV.length == 2
  @credentials[:organisation_key] = ARGV[0]
  @credentials[:uid] = ARGV[1]
  print "Enter password: "
  begin
    @credentials[:password] = STDIN.noecho(&:gets).chomp
  rescue SystemExit, Interrupt
    puts "[Aborted]"
    exit 0
  end
  puts ""
elsif ARGV.length == 3
  @credentials[:organisation_key] = ARGV[0]
  @credentials[:uid] = ARGV[1]
  @credentials[:password] = ARGV[2]
else
  puts "Usage: puavo-bughunter <organisation name> <username> [<password>]"
  puts "Password will be prompted for if not given"
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

# devices without schools
def device_in_nonexistent_school
  Device.all.each do |d|
    if d.puavoSchool.nil?
      # this cannot happen, but let's check for it anyway
      puts "Device \"#{d.cn}\" does not have a puavoSchool setting at all! This cannot happen! What did you do?!"
      next
    end

    begin
      School.find(d.puavoSchool)
    rescue ActiveLdap::EntryNotFound => e
      puts "Device \"#{d.cn}\" is owned by a non-existent school \"#{d.puavoSchool}\""
    end
  end
end

# device with invalid/non-existent puavoPreferredServer
def device_with_invalid_preferred_server
  Device.all.each do |d|
    s = begin d.puavoPreferredServer rescue nil end

    if s
      begin
        Device.find(s)
      rescue ActiveLdap::EntryNotFound => e
        puts "The preferredPuavoServer of device \"#{d.cn}\" does not exist"
      end
    end
  end
end

# device with a non-existent primary user (the UI ignores this silently)
def device_with_invalid_primary_user
  Device.all.each do |d|
    if d.puavoDevicePrimaryUser
      begin
        User.find(d.puavoDevicePrimaryUser)
      rescue ActiveLdap::EntryNotFound => e
        puts "The primary user \"#{d.puavoDevicePrimaryUser}\" of device \"#{d.cn}\" does not exist"
      end
    end
  end
end

# users whose school does not exist
def users_with_nonexistent_school
  User.all.each do |u|
    begin
      School.find(u.puavoSchool)
    rescue ActiveLdap::EntryNotFound => e
      puts "User \"#{u.cn}\" belongs to a non-existent school \"#{u.puavoSchool}\""
    end
  end
end

# missing users
def nonexistent_users_in_schools
  School.all.each do |s|
    Array(s.member || []).each do |m|
      begin
        User.find(m)
      rescue
        puts "User \"#{m}\" in school \"#{s.cn}\" does not exist"
      end
    end
  end
end

# users who share a "unique" external ID
def shared_external_ids
  eid = {}

  User.all.each do |u|
    next if u.puavoExternalId.nil? or u.puavoExternalId.empty?
    eid[u.puavoExternalId] ||= []
    eid[u.puavoExternalId] << [u.cn, u.id]
  end

  eid.each do |id, users|
    if users.count > 1
      puts "External ID \"#{id}\" is used by #{users.count} users:"
      users.each {|name, pid| puts "  #{name} (id #{pid})" }
    end
  end
end

# deleted organisation owners (this was fixed in Puavo long ago, but old users can still exist)
def missing_organisation_owners
  # remove the puavo user, it never "exists"
  owners = LdapOrganisation.current.owner.each.select { |dn| dn != "uid=admin,o=puavo" }

  owners.each do |o|
    begin
      User.find(o.rdns[0]["puavoId"])
    rescue
      puts "Organisation owner \"#{o}\" does not exist"
    end
  end
end

def groups_with_missing_schools
  Group.all.each do |g|
    begin
      School.find(g.puavoSchool)
    rescue
      puts "Group \"#{g.cn}\" belongs to a non-existent school \"#{g.puavoSchool}\""
    end
  end
end

def groups_without_type
  Group.all.each do |g|
    if g.puavoEduGroupType.nil? or g.puavoEduGroupType.empty?
      begin
        s = School.find(g.puavoSchool)
      rescue
        s = nil
      end
      puts "Group \"#{g.cn}\" in school \"#{s.nil? ? "<MISSING>" : s.cn}\" does not have a type (teaching/administrative/etc.) set"
    end
  end
end

def bootservers_with_missing_schools
  Server.all.each do |b|
    Array(b.puavoSchool || []).each do |s|
      begin
        School.find(s)
      rescue
        puts "Bootserver \"#{b.cn}\" serves a non-existent school \"#{s}\""
      end
    end
  end
end

puts '-' * 25

tests = [
  # organisation
  method(:missing_organisation_owners),
  method(:bootservers_with_missing_schools),

  # users
  method(:users_with_nonexistent_school),
  method(:nonexistent_users_in_schools),
  method(:shared_external_ids),

  # groups
  method(:groups_with_missing_schools),
  method(:groups_without_type),

  # devices
  method(:device_in_nonexistent_school),
  method(:device_with_invalid_preferred_server),
  method(:device_with_invalid_primary_user),
]

tests.each do |t|
  begin
    t.call
  rescue
    puts "ERROR: Test #{t} caused an exception! Please investigate!"
  end
end

puts '-' * 25
puts 'All tests done'

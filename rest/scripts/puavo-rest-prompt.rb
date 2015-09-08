#!/usr/bin/ruby1.9.1

require 'bundler/setup'
require_relative "../puavo-rest"
require "pry"
require "io/console"
require "puavo/etc"

REDIS_CONNECTION = Redis.new CONFIG["redis"].symbolize_keys

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

module PuavoRest

  @domain = ask "Organisation domain", :default => PUAVO_ETC.get(:domain)
  @credentials = {}
  u = ask("Username", :default => PUAVO_ETC.get(:ldap_dn))
  if LdapModel.is_dn(u)
    @credentials[:dn] = u
  else
    @credentials[:username] = u
  end

  STDIN.noecho do
    @credentials[:password] = ask("Password", :default => PUAVO_ETC.get(:ldap_password))
  end

  LdapModel.setup(:rest_root => "https://#{ @domain }")

  def self.as_user
    LdapModel.setup(
      :organisation => Organisation.by_domain!(@domain),
      :credentials => @credentials
    )
    "You are now #{ User.current["username"] }"
  end

  def self.as_server
    LdapModel.setup(:credentials => CONFIG["server"])
    "You are now #{ User.current["username"] }"
  end

  puts
  puts
  puts as_user
  puts
  puts "Use as_server to act as server and as_user to return to user"
  binding.pry
end


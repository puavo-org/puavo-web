#!/usr/bin/ruby

require 'optparse'
require 'csv'

require 'bundler/setup'
require_relative "../puavo-rest"
require_relative "../lib/puavo_import"


include PuavoImport::Helpers

@options = PuavoImport.cmd_options(:message => "Set external id by username")

setup_connection(@options)


CSV.foreach(@options[:csv_file], :encoding => @options[:encoding], :col_sep => ";" ) do |row|
  data = encode_text(row, @options[:encoding])

  external_id = data[1]
  username = data[9]

  next if external_id.nil?
  next if username.nil?

  user = PuavoRest::User.by_username(username)
  if user.nil?
    puts "Cannot find user by: " + username.inspect
    next
  end

  user.external_id = external_id

  puts "Set external_id #{ external_id } to user: #{ user.username }"

  user.save!
end


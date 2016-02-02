#!/usr/bin/ruby1.9.1

require 'optparse'
require 'csv'

require 'bundler/setup'
require_relative "../puavo-rest"
require_relative "../lib/puavo_import"

include PuavoImport::Helpers

@options = cmd_options(:message => "Rename groups", :no_csv_file => true)

setup_connection(@options)

PuavoRest::Group.all.each do |group|
  next if !@options[:include_schools].include?(group.school_id.to_s)

  if name = group.name.match(/^([0-9-]{1,3})[\.]* luokka$/)
    new_name = name[1]
    res = ask("Rename group (school_id: #{ group.school_id }) #{ group.name } -> #{ new_name }", :default => "N")

    if res == "Y"
      puts "Update"
      group.name = new_name
      group.save!
    end
  end
end

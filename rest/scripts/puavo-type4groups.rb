#!/usr/bin/ruby1.9.1

require 'bundler/setup'
require_relative "../puavo-rest"
require_relative "../lib/puavo_import"

include PuavoImport::Helpers

@options = PuavoImport.cmd_options(:message => "Set type for groups")

setup_connection(@options)

group_type = {
  "1" => "teaching group",
  "2" => "year class",
  "3" => "administrative group",
  "4" => "other groups"
}

PuavoRest::Group.all.each do |group|
  next if !@options[:include_schools].include?(group.school_id.to_s)

  current_type = "1"
  group_type.each do |k,v|
    if v == group.type
      current_type = k
    end
  end

  type = ask("\nSelect type for group '#{ group.name }':\n" +
      group_type.map{ |k,v| k.to_s + ": " + v }.join("\n") + "\n",
      :default => current_type)

  next if group.type == group_type[type]
  puts "\nSet type #{ group_type[type] } for #{ group.name }"
  group.type = group_type[type]
  group.save!
end

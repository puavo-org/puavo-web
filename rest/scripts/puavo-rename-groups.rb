#!/usr/bin/ruby1.9.3

require 'optparse'
require 'csv'

require 'bundler/setup'
require_relative "../puavo-rest"
require_relative "../lib/puavo_import"

include PuavoImport::Helpers

options = cmd_options(:message => "Import schools to Puavo")

LdapModel.setup(
  :credentials => CONFIG["server"]
)

LdapModel.setup(
  :organisation => PuavoRest::Organisation.by_domain!(options[:organisation_domain])
)

PuavoRest::Group.all.each do |group|

  if name = group.name.match(/^([0-9-]{1,3})[\.]* luokka$/)
    new_name = name[1]
    puts "Rename group (school_id: #{ group.school_id }) #{ group.name } -> #{ new_name }"
    group.name = new_name
    #group.save!
  end
end

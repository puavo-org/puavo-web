#!/usr/bin/ruby1.9.3
# -*- coding: utf-8 -*-

require 'optparse'
require 'csv'

require 'bundler/setup'
require_relative "../puavo-rest"
require_relative "../lib/puavo_import"

options = PuavoImport.cmd_options(:message => "Import users to Puavo")

REDIS_CONNECTION = Redis.new CONFIG["redis"].symbolize_keys

LdapModel.setup(
  :credentials => CONFIG["server"]
)

LdapModel.setup(
  :organisation => PuavoRest::Organisation.by_domain!(options[:organisation_domain])
)

CSV.foreach(options[:csv_file], :encoding => options[:encoding] ) do |row|
  user_data = PuavoImport.csv_row_to_array(row, options[:encoding])
  PuavoImport::User.new(:external_id => user_data[0],
                        :first_name => user_data[1],
                        :last_name => user_data[2],
                        :email => user_data[3],
                        :telephone_number => user_data[4],
                        :preferred_language => user_data[5],
                        :group_external_id => user_data[6],
                        :school_external_id => user_data[7], # FIXME: multiple value for teacher?
                        :username => user_data[8])
end

mode = "default"

mode = "import" if options[:import]

case mode
when "import"
  puts "Import users\n\n"
  PuavoImport::User.all.each do |user|
    puavo_rest_user = PuavoRest::User.by_attr(:external_id, user.external_id)
    if puavo_rest_user
      if user.need_update?(puavo_rest_user)
        puts "#{ user.to_s }: update user information"
      else
        puts "#{ user.to_s }: no changes"
      end
    else
      puts "#{ user.to_s }: add user to Puavo"
      puavo_rest_user = PuavoRest::User.new(
        :external_id => user.external_id,
        :first_name => user.first_name,
        :last_name => user.last_name,
        :email => user.email,
        :telephone_number => user.telephone_number,
        :preferred_language => user.preferred_language,
        :username => user.username,
        :roles => ["student"], # FIXME teacher?
        :school_dns => [user.school.dn.to_s]).save!

    end

    # FIXME users groups (add/update)?

  end
end

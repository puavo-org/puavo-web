#!/usr/bin/ruby1.9.3
# -*- coding: utf-8 -*-

require 'optparse'
require 'csv'

require 'bundler/setup'
require_relative "../puavo-rest"
require_relative "../lib/puavo_import"

include PuavoImport::Helpers

options = PuavoImport.cmd_options(:message => "Import users to Puavo") do |opts, options|
  opts.on("--user-role ROLE", "Role of user (student/teacher)") do |r|
    options[:user_role] = r
  end

  opts.on("--teacher-group-suffix GROUP", "Group suffix for Teacher") do |g|
    options[:teacher_group_suffix] = g
  end
end

REDIS_CONNECTION = Redis.new CONFIG["redis"].symbolize_keys

LdapModel.setup(
  :credentials => CONFIG["server"]
)

LdapModel.setup(
  :organisation => PuavoRest::Organisation.by_domain!(options[:organisation_domain])
)

CSV.foreach(options[:csv_file], :encoding => options[:encoding], :col_sep => ";" ) do |row|
  user_data = encode_text(row, options[:encoding])
  PuavoImport::User.new(:external_id => user_data[0],
                        :first_name => user_data[1],
                        :last_name => user_data[2],
                        :email => user_data[3],
                        :telephone_number => user_data[4],
                        :preferred_language => user_data[5],
                        :group_external_id => user_data[6],
                        :school_external_id => user_data[7], # FIXME: multiple value for teacher?
                        :username => user_data[8],
                        :role => options[:user_role],
                        :teacher_group_suffix => options[:teacher_group_suffix])
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
        :roles => [options[:user_role]],
        :school_dns => [user.school.dn.to_s])
      puavo_rest_user.save!

    end

    group_found = false
    puavo_rest_user.groups.each do |g|
      if g.id != user.group.id
        unless g.external_id.nil?
          puts "\tRemove group: #{ g.name }"
          g.remove_member(puavo_rest_user)
          g.save!
        end
      else
        group_found = true
      end
    end

    unless group_found
      puts "\tAdd group: #{ user.group.name }"
      user.group.add_member(puavo_rest_user)
      user.group.save!
    end

  end
end

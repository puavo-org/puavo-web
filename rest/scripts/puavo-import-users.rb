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

  opts.on("--skip-schools x,y,z", Array) do |skip_schools|
    options[:skip_schools] = skip_schools
  end
end

REDIS_CONNECTION = Redis.new CONFIG["redis"].symbolize_keys

LdapModel.setup(
  :credentials => CONFIG["server"]
)

LdapModel.setup(
  :organisation => PuavoRest::Organisation.by_domain!(options[:organisation_domain])
)

users = []

CSV.foreach(options[:csv_file], :encoding => options[:encoding], :col_sep => ";" ) do |row|
  user_data = encode_text(row, options[:encoding])

  school_external_ids = user_data[8].nil? ? [] : Array(user_data[8].split(","))

  school_external_ids.delete_if do |school_id|
    options[:skip_schools].include?(school_id.to_s)
  end if options[:skip_schools]

  next if school_external_ids.empty?

  begin
    user = PuavoImport::User.new(:db_id => user_data[0],
                                 :external_id => user_data[1],
                                 :first_name => user_data[2],
                                 :given_names => user_data[3],
                                 :last_name => user_data[4],
                                 :email => user_data[5],
                                 :telephone_number => user_data[6],
                                 :preferred_language => user_data[7],
                                 :group_external_id => user_data[10],
                                 :username => user_data[9],
                                 :school_external_ids => school_external_ids, # FIXME: multiple value for teacher?
                                 :role => options[:user_role],
                                 :teacher_group_suffix => options[:teacher_group_suffix])
  rescue PuavoImport::UserGroupError => e
    puts e.to_s
    next
  end

  if user.schools.empty?
    STDERR.puts "Cannot find school (#{ user.school_external_ids }) for user: #{ user }"
  else
    users.push(user)
  end

end

mode = options[:mode]

case mode
when "set-external-id"

  users.each do |user|

    next if PuavoRest::User.by_attr(:external_id, user.external_id)

    puavo_users = PuavoRest::User.by_attrs({ :first_name => user.first_name,
                                             :last_name => user.last_name },
                                           { :multiple => true } )

    if puavo_users.empty?
      puavo_users = PuavoRest::User.by_attrs({ :first_name => user.given_names,
                                               :last_name => user.first_name },
                                             { :multiple => true } )
    end

    if puavo_users.empty?
      (user.given_names.split(" ") +
       [user.first_name,
        user.last_name]).uniq.permutation(2).each do |names|
        puavo_user = PuavoRest::User.by_attrs({ :first_name => names[0],
                                                :last_name => names[1] },
                                              { :multiple => true } )
        unless Array(puavo_user).empty?
          break
        end
      end
    end


    if puavo_users.empty?
      next
    end

    puavo_user = puavo_users.first

    if puavo_users.length > 1
      user_count = 0

      puts "\nImport user:"
      puts "first name: #{ user.first_name }"
      puts "given names: #{ user.given_names }"
      puts "last_name: #{ user.last_name }"
      puts "schools: " + user.import_school_names
      puts "group: #{ user.import_group_name }" if user.group
      puts

      puavo_users.each do |u|
        groups = u.groups.map{ |g| "'#{ g.name}'" }.join(", ")
        puts "#{ user_count } #{ u.first_name } #{ u.last_name }, #{ u.username }, #{ u.school.name }, #{ u.import_group_name }, last login: xxxxx"
        user_count += 1
      end

      while(true) do
        response = ask("Choose the right user")

        number = response.to_i

        if puavo_users[number]
          puavo_user = puavo_users[number]
          break
        end
      end

    end

    different_attributes = diff_objects(puavo_user, user, ["first_name",
                                                           "last_name",
                                                           "import_school_names",
                                                           "import_group_name",
                                                           "external_id"] )

    response = "Y"

    if different_attributes.length > 1
      response = ask("Update external_id (#{ user.external_id }) to Puavo (Y/N)?",
                     :default => "N")
    end

    if response == "Y"
      puts "Update external id"
      puavo_user.external_id = user.external_id
      # puavo_user.external_data = FIXME
      puavo_user.save!
    else
      puts "Skip user: " + user.to_s
    end

    puts "\n" + "-" * 100 + "\n\n"
  end

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

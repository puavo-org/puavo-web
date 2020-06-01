#!/usr/bin/ruby
# -*- coding: utf-8 -*-

require 'optparse'
require 'csv'
require "elasticsearch"

require 'bundler/setup'
require_relative "../puavo-rest"
require_relative "../lib/puavo_import"

include PuavoImport::Helpers

def last_login(domain, username)

  if @options[:es_url].nil?
    return "Can't get lastlogin"
  end

  if @es_client.nil?
    @es_client = Elasticsearch::Client.new(:url => @options[:es_url])
  end

  timestamp = nil
  today = Date.today
  indices = (1..180).map do |i|
    (today - i).strftime("fluentd-puavo-rest-%Y.%m.%d")
  end

  indices.each do |indice|
    begin
      query = "msg: \"created session\" AND created\\ session.session.organisation: \"#{ domain }\" AND created\\ session.session.user.username: \"#{ username }\""
      res = @es_client.search({
                          :ignore_unavailable => true,
                          :index => Array(indice),
                          :body => {
                            :_source => true,
                            :sort =>  { "@timestamp" => { :order => "asc" }},
                            :query => {
                              :filtered => {
                                :query => {
                                  :query_string => {
                                    :analyze_wildcard => true,
                                    :query => query
                                  }
                                }
                              }
                            }
                          }
                        })
      if res["hits"]["total"] > 0
        timestamp = res["hits"]["hits"][0]["_source"]["@timestamp"]
        break
      end

    rescue Elasticsearch::Transport::Transport::Errors::NotFound => err
      STDERR.puts err.to_s
      STDERR.puts
      STDERR.puts "Cannot find login timestamp"
    end

  end

  return timestamp

end

def update_user_groups(puavo_rest_user, user)
  case @options[:user_role]
  when "student"
    puavo_rest_user.teaching_group = user.teaching_group
    if user.year_class != user.teaching_group
      # FIXME: create year class if it not found?
      # FIXME: add user to yeah class
      #puavo_rest_user.year_class = user.year_class
    end
  when "teacher"
    puavo_rest_user.add_administrative_group(user.group)
  when "staff"
    puavo_rest_user.add_administrative_group(user.group)
  end
end

def update_puavo_rest_user_attributes(puavo_rest_user, user, attributes)
  attributes.each do |attribute|
    puavo_rest_user.send("#{ attribute }=", user.send(attribute.to_s))
  end
  puavo_rest_user.school_dns = [user.school.dn.to_s]
end

def create_puavo_rest_user(user, attributes)
  puavo_rest_user = PuavoRest::User.new
  attributes.each do |attribute|
    value = user.send(attribute.to_s)
    next if value.nil?
    puavo_rest_user.send("#{ attribute }=", value)
  end

  puavo_rest_user.external_id = user.external_id
  puavo_rest_user.roles = [@options[:user_role]]
  puavo_rest_user.school_dns = [user.school.dn.to_s]
  puavo_rest_user.username = user.username

  puavo_rest_user
end

YEAR_CLASS_TYPE = 'year class'

def yc_group_abbr(school, group_name)
  "#{school.abbreviation}-yc-#{group_name}"
end

# Creates new year class groups and updates existing ones.
# In diff mode, nothing is actually done.
def create_and_update_year_classes(users, diff_only)
  checked = Set.new

  users.each do |user|
    next if user.year_class.nil? || user.year_class.empty?

    yc_abbr = yc_group_abbr(user.school, user.year_class)

    # check each year class only once
    next if checked.include?(yc_abbr)
    checked << yc_abbr

    yc_group = PuavoRest::Group.by_attrs(:abbreviation => yc_abbr,
                                         :school_dn => user.school.dn)

    unless yc_group
      # The group does not exist, create it
      msg = "Creating a new year class group \"#{user.year_class}\" (abbreviation " \
            "\"#{yc_abbr}\") in school \"#{user.school.name}\""

      if diff_only
        puts brown(msg)
      else
        puts msg
      end

      next if diff_only

      yc_group = PuavoRest::Group.new(
        :name => user.year_class,
        :abbreviation => yc_abbr,
        :type => YEAR_CLASS_TYPE,
        :school_dn => user.school.dn
      )

      begin
        yc_group.save!
      rescue StandardError => e
        puts "Could not create a new year class group \"#{yc_abbr}\" in school " \
             "\"#{user.school.name}\": #{e}"
        puts "Stopping here"
        exit 1
      end
    else
      # The group exists, make sure it's type is "year class". Year class
      # groups don't have external IDs because they're synthetic groups,
      # created by this script.
      if yc_group.name != user.year_class ||
           yc_group.type != YEAR_CLASS_TYPE ||
           yc_group.external_id

        msg = "Year class \"#{yc_abbr}\" already exists, but it's name, " \
              "type or external ID are wrong, fixing"

        if diff_only
          puts green(msg)
        else
          puts msg
        end

        next if diff_only

        yc_group.name = user.year_class
        yc_group.type = YEAR_CLASS_TYPE
        yc_group.external_id = nil

        begin
          yc_group.save!
        rescue StandardError => e
          # This is NOT a fatal error
          puts "Could not update existing year class group \"#{yc_abbr}\" in " \
               "school \"#{user.school.name}\": #{e}"
        end
      else
        puts "Year class group \"#{yc_abbr}\": no changes"
      end
    end
  end

  # salli usea: PuavoRest::Group.by_attrs({:name => "..."}, {:multiple => true})
end

@options = PuavoImport.cmd_options(:message => "Import users to Puavo") do |opts, options|
  opts.on("--user-role ROLE", "Role of user (student/teacher)") do |r|
    options[:user_role] = r
  end

  opts.on("--group-suffix GROUP", "Group suffix for Teacher or Staff") do |g|
    options[:group_suffix] = g
  end

  opts.on("--matches x,y,x", Array) do |matches|
    options[:matches] = matches
  end

  opts.on("--not-skip-duplicate-user", "Handle duplicate puavo users") do |not_skip_duplicate_user|
    options[:not_skip_duplicate_user] = not_skip_duplicate_user
  end

  opts.on("--es-url ES_URL", "URL for Elasticsearch") do |es_url|
    options[:es_url] = es_url
  end

  opts.on("--update-usernames", "Actually change changed usernames. RUN THIS MANUALLY!") do |update|
    options[:update_usernames] = update
  end
end

setup_connection(@options)

users = []

invalid_school = 0
invalid_group = 0
user_not_found_by_name = 0
found_many_users_by_name = 0
correct_csv_users = 0
update_external_id = 0
not_update_external_id = 0

mode = @options[:mode]

students_without_year_class = []

CSV.parse(convert_text_file(@options[:csv_file]), :encoding => 'utf-8', :col_sep => ';') do |user_data|
  user_data_hash = {
    :db_id => user_data[0],
    :external_id => user_data[1],
    :first_name => user_data[2],
    :given_names => user_data[3],
    :last_name => user_data[4],
    :email => user_data[5],
    :telephone_number => user_data[6].to_s.gsub(/^-/, ""),
    :preferred_language => user_data[7],
    :username => user_data[9],
    :role => @options[:user_role]
  }

  if @options[:user_role] == "student"
    user_data_hash.merge!({
      :school_external_id => user_data[8],
      :teaching_group_external_id => user_data[10],
      :year_class => user_data[11]
    })
  end

  if @options[:user_role] == "teacher" || @options[:user_role] == "staff"
    user_data_hash.merge!({
      :school_external_id => user_data[10],
      :group_suffix => @options[:group_suffix],
      :secodary_school_external_ids => user_data[8].nil? ? [] : Array(user_data[8].split(","))
    })
  end

  school_id = user_data_hash[:school_external_id].to_s

  if @options.include?(:include_schools) && !@options[:include_schools].include?(school_id)
    puts "Ignoring user \"#{user_data_hash[:first_name]} #{user_data_hash[:last_name]}\" (username=\"#{user_data_hash[:username]}\") " \
         "because the school ID (#{school_id}) is not on the list of imported schools"
    next
  end

  if user_data_hash[:username].nil? || user_data_hash[:username].empty?
    puts "Ignoring user \"#{user_data_hash[:first_name]} #{user_data_hash[:last_name]}\" because the username is empty"
    next
  end

  begin
    user = PuavoImport::User.new(user_data_hash)
  rescue PuavoImport::UserGroupError => e
    puts e.to_s
    invalid_group += 1
    next
  end

  if user.school.nil?
    puts "Cannot find school (#{ user.school_external_ids }) for user: #{ user }"
    invalid_school += 1
    next
  end

  if @options[:user_role] == "student"
    # Loudly report students who don't have a year class set
    if user_data[11].nil? || user_data[11].empty?
      puts "ERROR: Student \"#{user_data_hash[:first_name]} #{user_data_hash[:last_name]}\" " \
           "in school \"#{user.school.name}\" has no year class"

      students_without_year_class << {
        name: "#{user_data_hash[:first_name]} #{user_data_hash[:last_name]}",
        school: user.school.name
      }
    end
  end

  correct_csv_users += 1
  users.push(user)

end

unless students_without_year_class.empty?
  # Be loud. Very loud.
  puts "FATAL: Found #{students_without_year_class.count} student(s) without a year class:"

  students_without_year_class.each do |s|
    puts "  Name: \"#{s[:name]}\"  School: \"#{s[:school]}\""
  end
end

if @options[:user_role] == "student"
  create_and_update_year_classes(users, mode == 'diff')
end

case mode
when "set-external-id"

  users.each do |user|

    if PuavoRest::User.by_attr(:external_id, user.external_id)
      next
    end

    puts "\n" + "-" * 100 + "\n\n"

    puavo_users = PuavoRest::User.by_attrs({ :first_name => user.first_name,
                                             :last_name => user.last_name,
                                             :roles => @options[:user_role]},
                                           { :multiple => true } )

    if puavo_users.empty?
      user_not_found_by_name += 1
      log_to_file("user_not_found_by_name")[:file].puts(user.to_s)
      next
    end

    puavo_user = puavo_users.first

    if puavo_users.length > 1
      found_many_users_by_name += 1
      log_to_file("found_many_users_by_name")[:file].puts user.to_s
      user_count = 0

      next unless @options[:not_skip_duplicate_user]

      puts "\nImport user:"
      puts "first name: #{ user.first_name }"
      puts "given names: #{ user.given_names }"
      puts "last_name: #{ user.last_name }"
      puts "school: " + user.import_school_name
      puts "group: #{ user.import_group_name }"
      puts

      puavo_users.each do |u|
        timestamp = last_login(@options[:organisation_domain], u.username)
        groups = u.groups.map{ |g| "'#{ g.name}'" }.join(", ")
        puts "#{ user_count } #{ u.first_name } #{ u.last_name }, #{ u.username }, #{ u.school.name }, #{ u.import_group_name }, last login (last 6 months): #{ timestamp }"
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
                                                           "import_school_name",
                                                           "import_group_name",
                                                           "external_id"] )

    response = "Y"

    if user.import_school_name != puavo_user.import_school_name
      response = "N"
    end

    if user.import_group_name.to_i != puavo_user.import_group_name.to_i
      response = "N"
    end

    #response = ask("Update external_id (#{ user.external_id }) to Puavo (Y/N)?",
    #               :default => "N")

    if response == "N"
      not_update_external_id += 1
      log_to_file("not_update_external_id")[:file].puts user.to_s
      next
    end

    puts "Update external id"
    puavo_user.external_id = user.external_id
    # puavo_user.external_data = FIXME
    puavo_user.save!
    update_external_id += 1

  end

  puts "correct_csv_users: #{ correct_csv_users }"
  puts "invalid_school: #{ invalid_school }"
  puts "invalid_group: #{ invalid_group }"
  puts "user_not_found_by_name: #{ user_not_found_by_name } file: #{ log_to_file("user_not_found_by_name")[:filename] }"
  puts "found_many_users_by_name: #{ found_many_users_by_name } file: #{ log_to_file("found_many_users_by_name")[:filename] }"
  puts "update_external_id: #{ update_external_id }"
  puts "not_update_external_id: #{ not_update_external_id } file: #{ log_to_file("not_update_external_id")[:filename] }"


when "diff-usernames"
  puts "Diff usernames\n\n"
  PuavoImport::User.all.each do |user|
    puavo_rest_user = PuavoRest::User.by_attr(:external_id, user.external_id)

    unless puavo_rest_user
      #puts "User not found from puavo: #{ user.to_s }"
      next
    end

    if user.username.nil?
      #puts "Username is not set: #{ user.to_s }"
      next
    end

    if user.username != puavo_rest_user.username
      puts "Username has changed: #{ puavo_rest_user.username } -> #{ user.username }"
    end
  end

when "diff"
  puts "Diff users\n\n"
  PuavoImport::User.all.each do |user|
    puavo_rest_user = PuavoRest::User.by_attr(:external_id, user.external_id)

    unless puavo_rest_user
      puts brown("Add new user: #{ user.to_s }")

      if @options[:user_role] == "student"
        puts brown("Adding user \"#{user.username}\" to year class group \"#{user.year_class}\"")
      end

      next
    end

    if !user.need_update?(puavo_rest_user) && @options[:silent]
      next
    end

    different_attributes = diff_objects(puavo_rest_user, user, ["first_name",
                                                                "last_name",
                                                                "username",
                                                                "email",
                                                                "telephone_number",
                                                                "import_school_name",
                                                                "import_group_name",
                                                                "import_group_external_id",
                                                                "import_role",
                                                                "external_id"] )

    puts "\n" + "-" * 100 + "\n\n"
  end

when "import"
  puts "Import users (#{ @options[:user_role] })\n\n"

  @new_users_by_school = {}

  PuavoImport::User.all.each do |user|
    # This has actually happened in production
    if user.username.nil? || user.username.empty?
      puts "ERROR: User \"#{user.first_name} #{user.last_name}\" has no username, skipping"
      next
    end

    begin
      puavo_rest_user = PuavoRest::User.by_attr(:external_id, user.external_id)

      yc_group = nil

      if user.year_class && !user.year_class.empty?
        yc_group = PuavoRest::Group.by_attrs(:abbreviation => yc_group_abbr(user.school, user.year_class))
      end

      if puavo_rest_user
        update_year_class = yc_group && puavo_rest_user.year_class_changed?(yc_group)

        # username updates are done only if specifically requested for
        update_username = user.username != puavo_rest_user.username && @options[:update_usernames]

        if user.need_update?(puavo_rest_user) || puavo_rest_user.removal_request_time || update_year_class || update_username
          puts "#{ puavo_rest_user["username"] } (#{ puavo_rest_user.import_school_name }): update user information"

          if puavo_rest_user.removal_request_time
            # Clear the deletion set timestamp: this user's information is being updated,
            # so clearly they cannot be marked for deletion yet.
            puts "User \"#{puavo_rest_user.username}\" (external ID \"#{puavo_rest_user.external_id}\") exists in the CSV file, but has been marked for deletion, clearing the removal mark"
            puavo_rest_user.removal_request_time = nil

            # Unlock too
            if puavo_rest_user.locked
              puts "Unlocking user \"#{puavo_rest_user.username}\" (external ID \"#{puavo_rest_user.external_id}\")"
              puavo_rest_user.locked = false
            end
          end

          update_attributes = [ :first_name,
                                :last_name,
                                :email,
                                :telephone_number ]

          update_attributes << :username if update_username

          # Our support system requires that each user must have an email address if they want to
          # create a new ticket, but some users only set their address manually when needed, so
          # don't clear out those manually-entered email addresses
          update_attributes.delete(:email) if user.email.nil?

          update_puavo_rest_user_attributes(puavo_rest_user, user, update_attributes)

          # This does nothing if the role already is correct, so it's safe to always call it
          puavo_rest_user.import_role = user.role

          # FIXME: We can not modify the role because admin user is able to add more roles for the user
          #puavo_rest_user.role = options[:user_role]
          #puavo_rest_user.username = user.username # FIXME invalid data?
          #puavo_rest_user.preferred_language = user.preferred_language FIXME: use school fallback?

          begin
            puavo_rest_user.validate!
          rescue ValidationError => validation_errors
            errors = validation_errors.as_json
            invalid_attributes = errors[:error][:meta][:invalid_attributes].keys
            invalid_attributes.each do |attribute|
              update_attributes.delete(attribute)
              puts "attribute: #{attribute}, value: '#{ user.send(attribute.to_s) }', error: " +
                errors[:error][:meta][:invalid_attributes][attribute].map { |a|
                a[:message]
              }.join(", ")
            end

            puavo_rest_user = PuavoRest::User.by_attr(:external_id, user.external_id)

            update_puavo_rest_user_attributes(puavo_rest_user, user, update_attributes)
          end

          puavo_rest_user.save!

          update_user_groups(puavo_rest_user, user)

          if update_year_class
            puavo_rest_user.year_class = yc_group
          end

        else
          next if @options[:silent]
          puts "#{ puavo_rest_user["username"] }: no changes"
        end
      else
        if user.username.nil?
          puts "Can't create user, username is not defined (external_id: #{ user.external_id }, name: #{ user.first_name } #{ user.last_name }) )"
          next
        end
        if user.external_id.nil? || user.external_id.empty?
          puts "Can't create user, external_id is not defined (name: #{ user.first_name } #{ user.last_name })"
          next
        end
        puts "Create new user to Puavo: \"#{user.first_name} #{user.last_name}\" (username=#{ user.username }) (school=#{ user.school.name })"
        # FIXME send email notifications to school admin

        create_attributes = [ :first_name,
                              :last_name,
                              :telephone_number,
                              :email ]

        puavo_rest_user = create_puavo_rest_user(user, create_attributes)

        begin
          puavo_rest_user.save!
        rescue ValidationError => validation_errors
          errors = validation_errors.as_json
          invalid_attributes = errors[:error][:meta][:invalid_attributes].keys
          invalid_attributes.each do |attribute|
            create_attributes.delete(attribute)
            puts "attribute: #{attribute}, value: '#{ user.send(attribute.to_s) }', error: " +
              errors[:error][:meta][:invalid_attributes][attribute].map { |a|
              a[:message]
            }.join(", ")
          end

          puavo_rest_user = create_puavo_rest_user(user, create_attributes)
        end

        if puavo_rest_user.new?
          begin
            puavo_rest_user.save!
          rescue ValidationError
            puts "Cannot create user: #{puavo_rest_user.username}"
            next
          end
        end


        update_user_groups(puavo_rest_user, user)

        puavo_rest_user.year_class = yc_group

        unless @new_users_by_school.has_key?(puavo_rest_user.school.id)
          @new_users_by_school[puavo_rest_user.school.id] = []
        end
        @new_users_by_school[puavo_rest_user.school.id].push(puavo_rest_user)
      end
    rescue StandardError => e
      # Don't let one failed user terminate the whole process
      puts "Cannot import/update user #{user.username}: #{e}"
    end
  end

  begin
    @new_users_by_school.each do |school_id, users|
      list = PuavoRest::UserList.new(users.map{ |u| u.id })
      list.save
    end
  rescue StandardError => e
    puts "Username list creation did not succeed: #{e}"
  end

  schools = PuavoRest::School.all

  schools.each do |school|
    next unless @options.include?(:include_schools) && @options[:include_schools].include?(school.external_id)
    school_users = PuavoRest::User.by_attr(:school_dns, school.dn, :multiple => true)

    school_users.each do |user|
      begin
        next unless user.roles.include?(@options[:user_role])
        next unless PuavoImport::User.all.select{ |u| u.external_id.to_s == user.external_id.to_s }.empty?

        if user.removal_request_time.nil?
          # This user has been removed, but they have not been marked for deletion yet.
          # Set that mark now.
          puts "User \"#{user.username}\" (external ID \"#{user.external_id}\") exists in Puavo but not in the CSV file, marking the user for deletion and locking the account"
          user.removal_request_time = Time.now.utc
          user.locked = true
          user.save!
        end
      rescue StandardError => e
        # Don't let one failed user terminate the whole process
        puts "Could not update user \"#{user.first_name} #{user.last_name}\": #{e}"
      end
    end
  end

end

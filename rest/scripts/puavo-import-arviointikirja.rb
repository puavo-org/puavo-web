#!/usr/bin/ruby

require 'optparse'
require 'csv'
require 'date'
require 'time'

require 'byebug'
require 'pry'

require 'bundler/setup'
require_relative "../puavo-rest"
require_relative "../lib/puavo_import"

include PuavoImport::Helpers

options = PuavoImport.cmd_options(:message => "Automatically create and remove groups and maintain group memberships") do |opts, options|
  opts.on("--schools filename", "Schools CSV data") do |filename|
    options[:schools_csv] = filename
  end
end

setup_connection(options)

if options[:schools_csv].nil? || options[:schools_csv].empty?
  STDERR.puts "You must specify the schools CSV with --schools"
  exit 1
end

mode = options[:mode] || "default"
diff = mode == "diff"

# Turns the group name into usable (?) group abbreviation
REPLACEMENTS = {
  'äÄâÂáÁàÀåÅ'  => 'a',
  'öÖôÔóÓòÒ'    => 'o',
  'ëËêÊéÉèÈ€'   => 'e',
  'íÍìÌ'        => 'i',
  ' '           => '-',
}

def filter(name)
  REPLACEMENTS.each do |what, with|
    what.split('').each do |c|
      name.gsub!(c, with)
    end
  end

  name.gsub!(/[^a-z0-9\s]/i, '-')
  name.downcase[0..16]
end

def with_default(s, d)
  (s.nil? || s.empty?) ? d : s
end

# Load schools
schools = {}

begin
  CSV.parse(convert_text_file(options[:schools_csv]), :encoding => 'utf-8', :col_sep => ';') do |s|
    begin
      school = PuavoRest::School.by_attr(:abbreviation,
                                         s[2],
                                         :multiple => false)
    rescue StandardError => e
      puts red("Cannot retrieve school \"#{s[2]}\": #{e}")
      next
    end

    if school.nil?
      puts "WARNING: Cannot find school \"#{s[2]}\" (external ID \"#{s[0]}\")"
      next
    end

    schools[s[0].to_i] = school
  end
rescue StandardError => e
  puts "Cannot load schools: #{e}"
  exit 1
end

# Update groups
DATE_FORMAT = '%d.%m.%Y'
now = Time.now.localtime
today = Date.new(now.year, now.month, now.day)

used_external_ids = Set.new

have_errors = false

CSV.parse(convert_text_file(options[:csv_file]), :encoding => 'utf-8', :col_sep => ';') do |grp|
  group_name = grp[2]

  if group_name.nil? || group_name.empty?
    puts "Ignoring a group with an empty name"
    next
  end

  school_card = grp[1].to_i

  unless schools.include?(school_card)
    puts red("School \"#{school_card}\" not found in the schools CSV, cannot " \
             "import group \"#{group_name}\"")
    next
  end

  start_date = Date.strptime(with_default(grp[3], '01.01.2000'), DATE_FORMAT)
  end_date = Date.strptime(with_default(grp[4], '31.12.2999'), DATE_FORMAT)

  if start_date > end_date
    start_date, end_date = end_date, start_date
  end

  members = with_default(grp[5], '').split(',')

  external_id = grp[0]

  if used_external_ids.include?(external_id)
    puts red("ERROR: Group external ID \"#{external_id}\" is used more than once!")
    next
  end

  used_external_ids << external_id

  puavo_group = PuavoRest::Group.by_attr(:external_id,
                                         external_id,
                                         :multiple => true)

  if puavo_group.count > 1
    # This is a very bad situation
    puts "Found #{puavo_group.count} groups sharing the external ID \"#{external_id}\"."
    puts "This is a fatal error, stopping here. Please investigate."
    exit 1
  end

  # school_card has been validated already, the school is known to exist
  school = schools[school_card]
  group_abbr = "#{school.abbreviation}-#{filter(group_name.dup)}"

  if today < start_date || today > end_date
    # This group should not exist
    if puavo_group[0]
      puavo_group = puavo_group[0]

      # tell why the group is being deleted
      if today < start_date
        puts red("Deleting group \"#{group_name}\" (#{group_abbr}): " \
                 "the course won't start until on #{start_date}")
      else
        puts red("Deleting group \"#{group_name}\" (#{group_abbr}): " \
                 "the course ended on #{end_date}")
      end

      begin
        puavo_group.destroy! unless diff
      rescue StandardError => e
        puts red("ERROR: Could not delete group: #{e}")
        have_errors = true
      end
    end
  else
    # This group should exist
    update_members = true

    if puavo_group.count == 0
      # Create the group
      puts green("Creating group \"#{group_name}\" (#{group_abbr}): " \
                 "the course was started on #{start_date}")

      puavo_group = PuavoRest::Group.new(
        :name => group_name,
        :external_id => external_id,
        :abbreviation => group_abbr,
        :type => "course group",
        :school_dn => school.dn)

      begin
        puavo_group.save! unless diff
      rescue StandardError => e
        puts red("ERROR: Could not create group: #{e}")
        have_errors = true
        update_members = false
      end
    else
      # Update the group details
      puavo_group = puavo_group[0]
      do_it = false

      if puavo_group.type != "course group"
        puts brown("Updating group \"#{group_name}\" (#{group_abbr}) type " \
                   "(\"#{puavo_group.type}\" -> \"course group\")")
        puavo_group.type = "course group"
        do_it = true
      end

      if puavo_group.name != group_name
        puts brown("Updating group \"#{group_name}\" (#{group_abbr}) name " \
                   "(\"#{puavo_group.name}\" -> \"#{group_name}\")")
        puavo_group.name = group_name
        do_it = true
      end

      if puavo_group.abbreviation != group_abbr
        puts brown("Updating group \"#{group_name}\" (#{group_abbr}) abbreviation " \
                   "(\"#{puavo_group.abbreviation}\" -> \"#{group_abbr}\")")
        puavo_group.abbreviation = group_abbr
        do_it = true
      end

      begin
        puavo_group.save! if do_it && !diff
      rescue StandardError => e
        puts red("ERROR: Could not update group: #{e}")
        have_errors = true
        update_members = false
      end
    end

    next unless update_members

    # Update the group members list unless there were errors

    group_members = Set.new
    save_group = false

    # Add users to the group
    members.each do |hash|
      puavo_user = PuavoRest::User.by_attr(:external_id,
                                           hash,
                                           :multiple => true)

      if puavo_user.count == 0
        puts "WARNING: Cannot find user by external ID \"#{hash}\", " \
             "should be in group \"#{group_name}\" (#{group_abbr})"
        next
      end

      if puavo_user.count > 1
        # This should not happen
        puts red("Found #{puavo_user.count} users with the same external ID \"#{hash}\":")

        puavo_user.each do |u|
          puts "    \"#{u.username}\""
        end

        next
      end

      puavo_user = puavo_user[0]
      group_members << puavo_user.username

      unless puavo_group.has?(puavo_user)
        puts green("Adding user #{puavo_user.username} (#{hash}) to group " \
                   "\"#{group_name}\" (#{group_abbr})")

        unless diff
          begin
            puavo_group.add_member(puavo_user)
            save_group = true
          rescue StandardError => e
            puts red("ERROR: Could not add user to the group: #{e}")
            have_errors = true
          end
        end
      end
    end

    # Remove users from the group
    members = puavo_group.member_usernames.dup

    members.each do |m|
      next if group_members.include?(m)

      puts red("Removing user #{m} from group \"#{group_name}\" (#{group_abbr})")

      user = PuavoRest::User.by_attr(:username,
                                     m,
                                     :multiple => false)

      if user.nil?
        puts red("Could not find user #{m}")
        next
      end

      unless diff
        begin
          puavo_group.remove_member(user)
          save_group = true
        rescue StandardError => e
          puts red("ERROR: Could not remove user from the group: #{e}")
          have_errors = true
        end
      end
    end

    # Finally save the group
    if !diff && save_group
      begin
        puavo_group.save!
      rescue StandardError => e
        puts red("ERROR: Could not save the group: #{e}")
        have_errors = true
      end
    end
  end
end

exit 1 if have_errors
exit 0

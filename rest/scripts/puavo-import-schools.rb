#!/usr/bin/ruby

require 'optparse'
require 'csv'

require 'bundler/setup'
require_relative "../puavo-rest"
require_relative "../lib/puavo_import"

include PuavoImport::Helpers

options = cmd_options(:message => "Import schools to Puavo")

setup_connection(options)

if options[:include_schools]
  puts "Importing these schools: #{options[:include_schools].join(', ')}"
end

CSV.parse(convert_text_file(options[:csv_file]), :encoding => 'utf-8', :col_sep => ';') do |school_data|
  next if school_data[0].nil? || school_data[1].nil? || school_data[1].empty?

  if !options[:include_schools].nil? && !options[:include_schools].include?(school_data[0].to_s)
    puts "Ignoring school \"#{school_data[1]}\" because its school ID is not on the list of imported schools"
    next
  end

  if school_data[2].nil? || school_data[2].empty?
    puts "Ignoring school \"#{school_data[1]}\" because its external ID is missing or empty"
    next
  end

  PuavoImport::School.new(:external_id => school_data[0],
                          :name => school_data[1],
                          :abbreviation => school_data[2].downcase)
end

mode = options[:mode] || "default"

schools = PuavoImport::School.all

def ensure_administrative_group_exists(abbreviation, name,  school)
  group = PuavoRest::Group.by_attr(:abbreviation, abbreviation)

  if group
    # The group's name can be changed freely so we ignore it, but make sure
    # the type is correct.
    if group.type != "administrative group"
      puts brown("Updating the type of the group \"#{abbreviation}\"")

      begin
        group.type = "administrative group"
        group.save!
      rescue StandardError => e
        puts red("ERROR: Could not update the group: #{e}")
      end
    end
  else
    # Create a new group
    puts green("Creating new group \"#{name}\" (abbreviation \"#{abbreviation}\")")

    begin
      PuavoRest::Group.new(:name => name,
                           :abbreviation => abbreviation,
                           :type => "administrative group",
                           :school_dn => school.dn).save!
    rescue StandardError => e
      puts red("ERROR: Could not create a new group: #{e}")
    end
  end
end

case mode
when "diff"
  puts "Compare current data for import data\n\n"

  schools.each do |school|
    if school.abbreviation.nil?
      puts brown("Abbreviation is not defined (#{ school.name }) -> skip")
      next
    end

    puavo_rest_school = PuavoRest::School.by_attr(:external_id, school.external_id)

    unless puavo_rest_school
      puts green("Add new school: #{ school.to_s }")
      puts green("  Add the 'teachers' and 'staff' administrative groups")
      next
    end

    if !school.need_update?(puavo_rest_school) && options[:silent]
      next
    end

    diff_objects(puavo_rest_school, school, ["name", "abbreviation", "external_id"])

    puts "\n" + "-" * 100 + "\n\n"
  end
when "set-external-id"
  puts "Set external id\n\n"
  sticky_response = nil
  schools.each do |school|
    puavo_school = PuavoRest::School.by_attr(:name, school.name)

    if puavo_school.nil?
      puts "Can not find school from Puavo: #{ school.name }\n\n"
      next
    end

    diff_objects(puavo_school, school, ["name", "abbreviation", "external_id"])

    if puavo_school.external_id != school.external_id
      response = sticky_response

      response = ask("Update external_id (#{ school.external_id }) to Puavo (Y/N/!)?",
                                 :default => "N") if response.nil?
      if response == "!"
        sticky_response = response
      end

      if response == "Y"
        puts "Update external id"
        puavo_school.external_id = school.external_id
        puavo_school.save!
      end
    end

    puts "\n" + "-" * 100 + "\n\n"
  end

when "import"
  puts "Import schools\n\n"
  schools.each do |school|
    if school.abbreviation.nil?
      puts brown("Abbreviation is not defined (#{ school.name }) -> skip")
      next
    end

    puavo_rest_school = PuavoRest::School.by_attr(:external_id, school.external_id)

    if puavo_rest_school
      if school.need_update?(puavo_rest_school)
        puts "#{ school.to_s }: update school information"
        puavo_rest_school.name = school.name
        puavo_rest_school.abbreviation = school.abbreviation
        puavo_rest_school.save!
      else
        next if options[:silent]
        puts "#{ school.to_s }: no changes"
      end
    else
      puts "#{ school.to_s }: add school to Puavo"
      puavo_rest_school = PuavoRest::School.new(:name => school.name,
                            :external_id => school.external_id,
                                                :abbreviation => school.abbreviation)
      puavo_rest_school.save!
    end

    # Create/update the two required administrative groups
    ensure_administrative_group_exists("#{school.abbreviation}-henkilokunta",
                                       'Henkilökunta',
                                       puavo_rest_school)

    ensure_administrative_group_exists("#{school.abbreviation}-opettajat",
                                       'Opettajat',
                                       puavo_rest_school)
  end
end


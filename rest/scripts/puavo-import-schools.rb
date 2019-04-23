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

CSV.parse(convert_text_file(options[:csv_file]), :encoding => 'utf-8', :col_sep => ';') do |school|
  external_id = school[0]
  name = school[1]
  abbr = school[2]
  school_code = school[3] || nil

  if external_id.nil? || external_id.empty? || name.nil? || name.empty? || abbr.nil? || abbr.empty?
    puts "Ignoring incomplete school (external_id=\"#{external_id}\", name=\"#{name}\", abbreviation=\"#{abbr}\")"
    next
  end

  if !options[:include_schools].nil? && !options[:include_schools].include?(external_id.to_s)
    puts "Ignoring school \"#{name}\" (ID \"#{external_id}\")"
    next
  end

  PuavoImport::School.new(:external_id => external_id,
                          :name => name,
                          :abbreviation => abbr.downcase,
                          :school_code => school_code)
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
    puts green("Creating a new administrative group \"#{name}\" (abbreviation \"#{abbreviation}\")")

    begin
      PuavoRest::Group.new(:name => name,
                           :abbreviation => abbreviation,
                           :type => "administrative group",
                           :school_dn => school.dn).save!
    rescue StandardError => e
      puts red("ERROR: Could not create a new administrative group: #{e}")
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
      puts green("Add new school: #{ school.to_s } (abbreviation \"#{school.abbreviation}\", school code \"#{school.school_code}\")")
      puts green("  Add the 'teachers' and 'staff' administrative groups")
      next
    end

    if !school.need_update?(puavo_rest_school) && options[:silent]
      next
    end

    diff_objects(puavo_rest_school, school, ["name", "abbreviation", "external_id", "school_code"])

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
        puavo_rest_school.school_code = school.school_code
        puavo_rest_school.save!
      else
        next if options[:silent]
        puts "#{ school.to_s }: no changes"
      end
    else
      puts "#{ school.to_s }: add school to Puavo (abbreviation \"#{school.abbreviation}\")"
      puavo_rest_school = PuavoRest::School.new(:name => school.name,
                                                :external_id => school.external_id,
                                                :abbreviation => school.abbreviation,
                                                :school_code => school.school_code)
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


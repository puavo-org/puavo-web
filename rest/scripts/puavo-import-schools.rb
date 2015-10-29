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

CSV.foreach(options[:csv_file],
            :encoding => options[:encoding],
            :col_sep => ";") do |school_data|
  school_data = encode_text(school_data, options[:encoding])
  PuavoImport::School.new(:external_id => school_data[0],
                          :name => school_data[1],
                          :abbreviation => school_data[2])
end

mode = options[:mode] || "default"

schools = PuavoImport::School.all

case mode
when "default"
  puts "Compare"
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
        puts "#{ school.to_s }: no changes"
      end
    else
      puts "#{ school.to_s }: add school to Puavo"
      PuavoRest::School.new(:name => school.name,
                            :external_id => school.external_id,
                            :abbreviation => school.abbreviation).save!
    end
  end
end


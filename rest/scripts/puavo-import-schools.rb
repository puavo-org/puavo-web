#!/usr/bin/ruby1.9.3
# -*- coding: utf-8 -*-

require 'optparse'
require 'csv'

require 'bundler/setup'
require_relative "../puavo-rest"
require_relative "../lib/puavo_import"

options = PuavoImport.cmd_options(:message => "Import schools to Puavo")

REDIS_CONNECTION = Redis.new CONFIG["redis"].symbolize_keys
DISTRIBUTED_LOCK = Redlock::Client.new([REDIS_CONNECTION])

LdapModel.setup(
  :credentials => CONFIG["server"]
)

LdapModel.setup(
  :organisation => PuavoRest::Organisation.by_domain!(options[:organisation_domain])
)

CSV.foreach(options[:csv_file], :encoding => options[:encoding] ) do |row|
  school_data = PuavoImport.csv_row_to_array(row, options[:encoding])
  PuavoImport::School.new(:external_id => school_data[0],
                          :name => school_data[1])
end

mode = options[:mode] || "default"

case mode
when "default"
  puts "Compare"
when "set-external-id"
  puts "Set external id\n\n"
  PuavoImport::School.all.each do |school|
    puavo_school = PuavoRest::School.by_attr(:name, school.name)

    if puavo_school.nil?
      puts "Can not find school from Puavo: #{ school.name }\n\n"
      next
    end

    PuavoImport.diff_objects(puavo_school, school, ["name", "abbreviation", "external_id"])

    if puavo_school.external_id != school.external_id
      response = PuavoImport.ask("Update external_id (#{ school.external_id }) to Puavo (Y/N)?",
                                 :default => "N")
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
  PuavoImport::School.all.each do |school|
    puavo_rest_school = PuavoRest::School.by_attr(:external_id, school.external_id)
    if puavo_rest_school
      if school.need_update?(puavo_rest_school)
        puts "#{ school.to_s }: update name"
        puavo_rest_school.name = school.name
        # FIXME: update abbreviation?
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


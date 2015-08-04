#!/usr/bin/ruby1.9.3
# -*- coding: utf-8 -*-

require 'optparse'
require 'csv'

require 'bundler/setup'
require_relative "../puavo-rest"
require_relative "../lib/puavo_import"

options = PuavoImport.cmd_options

REDIS_CONNECTION = Redis.new CONFIG["redis"].symbolize_keys

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

mode = "default"

mode = "import" if options[:import]

case mode
when "default"
  puts "Compare"
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


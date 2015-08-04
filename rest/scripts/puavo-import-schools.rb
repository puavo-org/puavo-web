#!/usr/bin/ruby1.9.3
# -*- coding: utf-8 -*-

require 'optparse'
require 'csv'

require 'bundler/setup'
require_relative "../puavo-rest"
require_relative "../lib/puavo_import"

options = PuavoImport.cmd_options

REDIS_CONNECTION = Redis.new CONFIG["redis"].symbolize_keys

def parse_row(row, options)
  school_data = row.first.split(";")
  school_data.map do |data|
    data.encode('utf-8', options[:encoding])
  end
end

LdapModel.setup(
  :credentials => CONFIG["server"]
)

LdapModel.setup(
  :organisation => PuavoRest::Organisation.by_domain!(options[:organisation_domain])
)

CSV.foreach(options[:csv_file], :encoding => options[:encoding] ) do |row|
  school_data = parse_row(row, options)
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
      if puavo_rest_school.name != school.name
        puts "#{ school.to_s }: update name"
        puavo_rest_school.name = school.name
        puavo_rest_school.save!
      else
        puts "#{ school.to_s }: no changes"
      end
    else
      puts "#{ school.to_s }: add school to Puavo"
      abbveriation = school.name.downcase
      abbveriation.gsub!(/[åäö ]/, "å" => "a", "ä" => "a", "ö" => "o", " " => "-")
      abbveriation.gsub!(/[ÅÄÖ]/, "Å" => "a", "Ä" => "a", "Ö" => "o")
      abbveriation.gsub!(/[^a-z0-9-]/, "")
      PuavoRest::School.new(:name => school.name,
                            :external_id => school.external_id,
                            :abbreviation => abbveriation).save!
    end
  end
end


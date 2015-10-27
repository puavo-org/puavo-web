#!/usr/bin/ruby1.9.3

require 'optparse'
require 'csv'

require 'bundler/setup'
require_relative "../puavo-rest"
require_relative "../lib/puavo_import"

include PuavoImport::Helpers

options = cmd_options(:message => "Import groups to Puavo")

REDIS_CONNECTION = Redis.new CONFIG["redis"].symbolize_keys

LdapModel.setup(
  :credentials => CONFIG["server"]
)

LdapModel.setup(
  :organisation => PuavoRest::Organisation.by_domain!(options[:organisation_domain])
)

groups = []

CSV.foreach(options[:csv_file], :encoding => options[:encoding], :col_sep => ";") do |row|
  group_data = encode_text(row, options[:encoding])
  group = PuavoImport::Group.new(
    :external_id => group_data[0],
    :name => group_data[1],
    :school_external_id => group_data[2]
  )

  if group.school
    groups.push(group)
  else
    STDERR.puts "Puts cannot find school for data: #{ group_data.inspect }"
  end

end

case options[:mode]

when "set-external-id"

  puts "Set external id\n\n"

  groups.each do |group|

    puavo_group = PuavoRest::Group.by_attr(:external_id, group.external_id)

    if puavo_group.nil?
      puavo_group = PuavoRest::Group.by_attrs(
        :name => group.name,
        :school_dn => group.school.dn
      )
    end

    if puavo_group.nil?
      puts "Can not find group from Puavo: #{ group.name }\n\n"
      next
    end

    diff_objects(puavo_group, group, ["name", "external_id"])

    if puavo_group.external_id != group.external_id
      response = ask("Update external_id (#{ group.external_id }) to Puavo (Y/N)?",
                     :default => "N")
      if response == "Y"
        puts "Update external id"
        puavo_group.external_id = group.external_id
        puavo_group.save!
      end
    end

    puts "\n" + "-" * 100 + "\n\n"
  end
when "import"
  puts "Import groups\n\n"
  groups.each do |group|
    puavo_rest_group = PuavoRest::Group.by_attr(:external_id, group.external_id)
    if puavo_rest_group
      if group.need_update?(puavo_rest_group)
        puts "#{ group.to_s }: update group information"
        puavo_rest_group.name = group.name
        puavo_rest_group.abbreviation = group.abbreviation
        puavo_rest_group.school_dn = group.school.dn
        puavo_rest_group.save!
      else
        puts "#{ group.to_s }: no changes"
      end
    else
      puts "#{ group.to_s }: add group to Puavo"
      PuavoRest::Group.new(:name => group.name,
                           :external_id => group.external_id,
                           :abbreviation => group.abbreviation,
                           :school_dn => group.school.dn).save!
    end
  end
end

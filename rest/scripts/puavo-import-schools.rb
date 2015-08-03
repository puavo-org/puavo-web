#!/usr/bin/ruby1.9.3

require 'optparse'
require 'csv'


options = {}
parser = OptionParser.new do |opts|
  opts.banner = "Usage: puavo-import-schools [options]

Import schools to Puavo

"

  opts.on("--organisation-domain DOMAIN", "Domain of organisation") do |o|
    options[:organisation_domain] = o
  end

  opts.on("--csv-file FILE", "csv file with schools") do |o|
    options[:csv_file] = o
  end

  opts.on_tail("-h", "--help", "Show this message") do
    STDERR.puts opts
    Process.exit()
  end
end
parser.parse!

if options.keys.count != 2
  STDERR.puts("Invalid arguments")
  STDERR.puts(parser)
  Process.exit(1)
end

require 'bundler/setup'
require_relative "../puavo-rest"
require_relative "../lib/puavo_import"

REDIS_CONNECTION = Redis.new CONFIG["redis"].symbolize_keys

def parse_row(row)
  school_data = row.first.split(";")
  school_data.map do |data|
    data.encode('utf-8', 'iso8859-1')
  end
end

LdapModel.setup(
  :credentials => CONFIG["server"]
)

LdapModel.setup(
  :organisation => PuavoRest::Organisation.by_domain!(options[:organisation_domain])
)

PuavoRest::School.all.each do |school|
  puts school.name
end

CSV.foreach(options[:csv_file], :encoding => "ISO8859-1" ) do |row|
  school_data = parse_row(row)
  PuavoImport::School.new(:external_id => school_data[0],
                          :name => school_data[1])
end

mode = "default"

case mode
when "default"
  puts "Compare"
end


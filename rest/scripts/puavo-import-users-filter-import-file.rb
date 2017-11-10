#!/usr/bin/ruby

require 'csv'

filter_column = ARGV[0]
primary_file = ARGV[1]
filter_file = ARGV[2]
output_file = ARGV[3]

@filter_data = []

CSV.foreach(ARGV[2], :encoding => 'ISO8859-1', :col_sep => ";" ) do |row|
  next if row[filter_column.to_i].nil?
  @filter_data.push(row[filter_column.to_i])
end


output = File.open(output_file, 'w')
CSV.foreach(ARGV[1], :encoding => 'ISO8859-1', :col_sep => ";" ) do |row|
  next if @filter_data.include?(row[filter_column.to_i])
  output.puts row.join(";")
end
output.close

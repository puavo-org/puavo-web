#!/usr/bin/ruby

require 'csv'
require 'set'

# need convert_text_file()
require_relative "../lib/puavo_import"
include PuavoImport::Helpers

filter_column = ARGV[0].to_i

@filter_data = Set.new

CSV.parse(convert_text_file(ARGV[2]), :encoding => 'utf-8', :col_sep => ';') do |row|
  next if row[filter_column].nil?
  @filter_data << row[filter_column]
end

output = File.open(ARGV[3], 'wb')

# Regardless of what the input encoding is, we'll always output UTF-8 with a
# BOM. This is because the script that processes this output file uses the BOM
# to detect if the file is UTF-8 or 8-bit ASCII and we cannot tell it directly
# what the encoding is (--character-encoding is no longer used). BOMs shouldn't
# be used, but primusquery outputs it when UTF-8 encoding is requested. It'll
# be a beautiful day when I can remove all these encodings and just go with
# UTF-8 with no BOMs...
output.write [0xEF, 0xBB, 0xBF].pack('ccc')

CSV.parse(convert_text_file(ARGV[1]), :encoding => 'utf-8', :col_sep => ';') do |row|
  next if @filter_data.include?(row[filter_column])
  output.puts row.join(";")
end

output.close

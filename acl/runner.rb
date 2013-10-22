
Rails.env = 'test'

require './acl/data'
require './acl/helper'

require 'pp'

TEST_DIR = File.dirname(__FILE__) + "/test/"

def run_acl_tests

  if not ARGV.empty?
    ARGV.each do |file|
      puts "Loading #{ file }"
      require "./" + file
    end
  else
    Dir.foreach TEST_DIR do |file|
      next if [".", ".."].include? file
      file = TEST_DIR + file
      puts "Loading #{ file }"
      require "./" + file
    end
  end

  LDAPTestEnv.report

end

if __FILE__ == $0
  run_acl_tests
end

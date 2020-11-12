
Rails.env = 'test'

require './acl/data'
require './acl/helper'
require './generic_test_helpers'

require 'pp'

TEST_DIR = File.dirname(__FILE__) + "/test/"

def run_acl_tests

  if not ARGV.empty?
    ARGV.each do |file|
      puts "Loading #{ file }"
      require "./" + file
    end
  else
    Dir.glob("#{ TEST_DIR }/*_test.rb").sort.each do |file|
      puts "Loading #{ file }"
      require "./" + file
    end
  end

  LDAPTestEnv.report

end

@owner_dn, @owner_password = Puavo::Test.setup_test_connection

if __FILE__ == $0
  run_acl_tests
end

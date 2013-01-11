
ENV["RAILS_ENV"] ||= 'test'
require File.expand_path(File.dirname(__FILE__) + "/../config/environment") unless defined?(RAILS_ROOT)

require File.dirname(__FILE__) + "/data"
require File.dirname(__FILE__) + "/helper"

require 'pp'

TEST_DIR = File.dirname(__FILE__) + "/test/"

def run_acl_tests

  if not ARGV.empty?
    ARGV.each do |file|
      puts "Loading #{ file }"
      require file
    end
  else
    Dir.foreach TEST_DIR do |file|
      next if [".", ".."].include? file
      file = TEST_DIR + file
      puts "Loading #{ file }"
      require file
    end
  end

  LDAPTestEnv.report

end

if __FILE__ == $0
  run_acl_tests
end

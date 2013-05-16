
ENV['RACK_ENV'] = 'test'

module PuavoRest
  CONFIG = {
    "ldap" => "test",
    "ltsp_server_data_dir" => "/tmp/puavo-rest-test",
    "bootserver" => true
  }
end

require_relative "../root"

require 'minitest/autorun'
require 'rack/test'
require "timecop"
require "debugger"

# Include rack helpers and expose full application stack
class MiniTest::Spec
  include Rack::Test::Methods
  def app
    Rack::Builder.parse_file(File.dirname(__FILE__) + '/../config.ru').first
  end
end


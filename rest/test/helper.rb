
ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require "timecop"
require "debugger"

require_relative "../config.rb"
require_relative "../root"

# Include rack helpers and expose full application stack
class MiniTest::Spec
  include Rack::Test::Methods
  def app
    Rack::Builder.parse_file(File.dirname(__FILE__) + '/../config.ru').first
  end
end


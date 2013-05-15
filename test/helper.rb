
ENV['RACK_ENV'] = 'test'

require_relative '../root'
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


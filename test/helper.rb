
ENV['RACK_ENV'] = 'test'

require_relative "../credentials"
require_relative "../errors"
require_relative "../resources/base"
require_relative "../resources/external_files"
require_relative "../resources/users"

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


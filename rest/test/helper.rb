# Require net-ldap for ActiveLdap. Rails env require below should do this. Not
# sure why it is  not...
require "net-ldap"

ENV['RACK_ENV'] = 'test'

ENV["RAILS_ENV"] ||= 'test'
require File.expand_path("../../../config/environment", __FILE__)

def create_server(attrs)
  server = Server.new
  server.attributes = attrs
  server.puavoDeviceType = "ltspserver"
  server.save!
  server
end

def create_device(attrs)
  d = Device.new
  d.classes = ["top", "device", "puppetClient", "puavoNetbootDevice"]
  d.puavoDeviceType = "thinclient"
  d.macAddress = "bc:5f:f4:56:59:71"

  d.attributes = attrs
  d.save!
  d
end

def assert_200(res=nil)
  res ||= last_response
  assert_equal 200, res.status, "Body: #{ res.body }"
end


require 'minitest/autorun'
require 'rack/test'
require "timecop"
require 'nokogiri'
require "debugger"

require_relative '../../test/generic_test_helpers'
Puavo::Test.setup_test_connection

module Rack
  module Test
    DEFAULT_HOST = "example.opinsys.net"
  end
end

require_relative "../config.rb"
require_relative "../root"


# Puavo Activeldap models requires this require for some reason
require "RMagick"

# Include rack helpers and expose full application stack
class MiniTest::Spec
  include Rack::Test::Methods
  def app
    Rack::Builder.parse_file(File.dirname(__FILE__) + '/../config.ru').first
  end

  def css(selector)
      doc = Nokogiri::HTML(last_response.body)
      doc.css(selector)
  end
end


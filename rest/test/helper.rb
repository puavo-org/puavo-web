# Require net-ldap for ActiveLdap. Rails env require below should do this. Not
# sure why it is  not...
require "net-ldap"
require "fluent-logger"

ENV['RACK_ENV'] = 'test'

ENV["RAILS_ENV"] ||= 'test'
require File.expand_path("../../../config/environment", __FILE__)

class MockFluent
  attr_reader :data, :timed_data
  def initialize(opts={})
    @opts = opts
  end
  def post(*args)
    @data ||= []
    @data.push args
    return !@opts[:broken]
  end
  def post_with_time(*args)
    @timed_data ||= []
    @timed_data.push args
    return !@opts[:broken]
  end
end

def create_server(attrs)
  attrs[:puavoDeviceType] ||=  "ltspserver"

  server = Server.new
  server.attributes = attrs
  server.save!
  server
end

def create_device(attrs)
  attrs[:puavoDeviceType] ||=  "thinclient"
  attrs[:macAddress] ||= "bc:5f:f4:56:59:71"

  d = Device.new
  d.classes = ["top", "device", "puppetClient", "puavoNetbootDevice"]
  d.attributes = attrs
  d.save!
  d
end

def create_basic_data
  @school = School.create(
    :cn => "gryffindor",
    :displayName => "Gryffindor"
  )

  @user = User.new(
    :givenName => "Bob",
    :sn  => "Brown",
    :uid => "bob",
    :puavoEduPersonAffiliation => "student",
    :preferredLanguage => "en",
    :mail => "bob@example.com"
  )
  @user.set_password "secret"
  @user.puavoSchool = @school.dn
  @user.role_ids = [
    Role.find(:first, :attribute => "displayName", :value => "Maintenance").puavoId
  ]
  @user.save!

  @laptop = Device.new
  @laptop.classes = ["top", "device", "puppetClient", "puavoLocalbootDevice", "simpleSecurityObject"]
  @laptop.attributes = {
    :puavoHostname => "laptop1",
    :puavoDeviceType => "laptop",
    :macAddress => "00:60:2f:98:63:F8",
  }
  @laptop.puavoSchool = @school.dn
  @laptop.save!

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
require 'webmock/minitest'

require_relative '../../generic_test_helpers'
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

module Fixtures
  DIR = File.expand_path File.dirname(__FILE__)
  ICS_FILE = DIR + "/fixtures/ical.ics"

  # This timestamp is in the middle of events defined in the fixture
  ICS_TIME = Time.local(2014, 2, 12, 14, 5, 0)
end


ENV['RACK_ENV'] = 'test'

ENV["RAILS_ENV"] ||= 'test'
require File.expand_path("../../../config/environment", __FILE__)

def setup_connection
  test_organisation = Puavo::Organisation.find('example')
  default_ldap_configuration = ActiveLdap::Base.ensure_configuration
  # Setting up ldap configuration
  LdapBase.ldap_setup_connection( test_organisation.ldap_host,
                                  test_organisation.ldap_base,
                                  default_ldap_configuration["bind_dn"],
                                  default_ldap_configuration["password"] )

  @owner_dn = User.find(:first, :attribute => "uid", :value => test_organisation.owner).dn.to_s
  @owner_password = test_organisation.owner_pw

  LdapBase.ldap_setup_connection( test_organisation.ldap_host,
                                  test_organisation.ldap_base,
                                  @owner_dn,
                                  @owner_password )
end

setup_connection

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


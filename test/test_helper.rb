ENV["RAILS_ENV"] = "test"
require File.expand_path("../../config/environment", __FILE__)
require "rails/test_help"
require "minitest/rails"

def setup_connection
  test_organisation = Puavo::Organisation.find('example')
  default_ldap_configuration = ActiveLdap::Base.ensure_configuration

  # Setting up ldap configuration
  LdapBase.ldap_setup_connection(
    test_organisation.ldap_host,
    test_organisation.ldap_base,
    default_ldap_configuration["bind_dn"],
    default_ldap_configuration["password"]
  )



  owner = User.find(:first, :attribute => "uid", :value => test_organisation.owner)
  if owner.nil?
    raise "Cannot find organisation owner for 'example'. Organisation not created?"
  end
  @owner_dn = owner.dn.to_s
  @owner_password = test_organisation.owner_pw

  ExternalService.ldap_setup_connection(
    test_organisation.ldap_host,
    "o=puavo",
    "uid=admin,o=puavo",
    "password"
  )
end

setup_connection

# To add Capybara feature tests add `gem "minitest-rails-capybara"`
# to the test group in the Gemfile and uncomment the following:
# require "minitest/rails/capybara"

# Uncomment for awesome colorful output
# require "minitest/pride"


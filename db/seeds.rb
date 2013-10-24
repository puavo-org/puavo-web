# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#   
#   cities = City.create([{ :name => 'Chicago' }, { :name => 'Copenhagen' }])
#   Major.create(:name => 'Daley', :city => cities.first)
require "puavo/etc"

authentication = Puavo::Authentication.new
authentication.configure_ldap_connection({
    :dn => PUAVO_ETC.ldap_dn,
    :password => PUAVO_ETC.ldap_password,
    :organisation_key => PUAVO_ETC.domain.split(".", 2).first
})
authentication.authenticate

school = School.create(
  :cn => "gryffindor",
  :displayName => "Gryffindor"
)

user = User.new(
  :givenName => "Bob",
  :sn  => "Brown",
  :uid => "bob",
  :puavoEduPersonAffiliation => "student",
  :preferredLanguage => "en",
  :mail => "bob@example.com"
)
user.set_password "secret"
user.puavoSchool = school.dn
user.role_ids = [
  Role.find(:first, :attribute => "displayName", :value => "Maintenance").puavoId
]
user.save!

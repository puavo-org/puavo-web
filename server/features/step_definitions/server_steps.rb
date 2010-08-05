Before do |scenario|
  test_organisation = Puavo::Organisation.find('example')

  I18n.locale = :en

  owner_uid = test_organisation.value_by_key('owner')
  owner_pw = test_organisation.value_by_key('owner_pw')

  if owner_uid.nil? || owner_pw.nil?
    raise "#{test_organisation.name}: owner of the organisation is not defined. See config/organisations.yml"
  end

  default_ldap_configuration = ActiveLdap::Base.ensure_configuration
  LdapBase.ldap_setup_connection( test_organisation.ldap_host,
                                  test_organisation.ldap_base,
                                  default_ldap_configuration["bind_dn"],
                                  default_ldap_configuration["password"] )

  # FIXME, if does not make anything connection to IdPool test scenarios not work later
  IdPool.first

  unless owner = User.find(:first, :attribute => "uid", :value => owner_uid )
    raise "Not found user: #{owner_uid}. See config/ldap.yml or add a new owner of organisation (#{test_organisation.name})"
  end

  # Setting up ldap configuration
  LdapBase.ldap_setup_connection( test_organisation.ldap_host,
                                  test_organisation.ldap_base,
                                  owner.dn,
                                  owner_pw )

  IdPool.first

  Server.all.each do |s|
    s.destroy
  end
end

Given /^the following servers:$/ do |servers|
  Server.create!(servers.hashes)
end

When /^I delete the (\d+)(?:st|nd|rd|th) server$/ do |pos|
  visit servers_path
  within("table tr:nth-child(#{pos.to_i+1})") do
    click_link "Destroy"
  end
end

Then /^I should see the following servers:$/ do |expected_servers_table|
  expected_servers_table.diff!(tableish('table tr', 'td,th'))
end

Given /^I am logged in as "([^\"]*)" with password "([^\"]*)"$/ do |login, password|
  visit login_path
  fill_in("Login", :with => login)
  fill_in("Password", :with => password)
  click_button("Login")
  steps %Q{
      Then I should see "Login successful!"
  }
end

Given /^the following LDAP services:$/ do |ldap_service|
  set_ldap_admin_connection
  LdapService.create(ldap_service.hashes)
end

When /^I delete the (\d+)(?:st|nd|rd|th) LDAP service$/ do |pos|
  visit ldap_services_path
  within("table tr:nth-child(#{pos.to_i+1})") do
    click_link "Remove"
  end
end

Then /^I should see the following LDAP services:$/ do |expected_ldap_services_table|
  rows = find('table').all('tr')
  table = rows.map { |r| r.all('th,td')[0..1].map { |c| c.text.strip } }
  expected_ldap_services_table.diff!(table)
end

Then /^"([^"]*)" is not member of "([^"]*)" system group$/ do |uid, group_cn|
  set_ldap_admin_connection
  group = SystemGroup.find(group_cn)
  group.members.map{ |g| g.uid }.should_not include(uid)
end

Then /^I should bind "([^\"]*)" with "([^\"]*)" to ldap$/ do |dn, password|
  set_ldap_admin_connection
  ldap_service = LdapService.find(dn)
  ldap_service.bind(password)
  ldap_service.remove_connection
end

When /^I get the organisation JSON page with "([^\"]*)" and "([^\"]*)"$/ do |username, password|
  page.driver.browser.basic_authorize(username, password)
  
  visit "/users/organisation.json"
end

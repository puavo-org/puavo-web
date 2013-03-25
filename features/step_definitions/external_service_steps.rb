Given /^the following external services:$/ do |external_services|
  set_ldap_admin_connection
  ExternalService.create(external_services.hashes)
end

When /^I delete the (\d+)(?:st|nd|rd|th) external service$/ do |pos|
  visit external_services_path
  within("table tr:nth-child(#{pos.to_i+1})") do
    click_link "Remove"
  end
end

Then /^I should see the following external services:$/ do |expected_external_services_table|
  expected_external_services_table.diff!( tableish('table tr', 'td,th').map{ |a| a[0..1] } )
end

Then /^"([^"]*)" is not member of "([^"]*)" system group$/ do |uid, group_cn|
  set_ldap_admin_connection
  group = SystemGroup.find(group_cn)
  group.members.map{ |g| g.uid }.should_not include(uid)
end

Then /^I should bind "([^\"]*)" with "([^\"]*)" to ldap$/ do |dn, password|
  set_ldap_admin_connection
  external_service = ExternalService.find(dn)
  external_service.bind(password)
  external_service.remove_connection
end

When /^I get the organisation JSON page with "([^\"]*)" and "([^\"]*)"$/ do |username, password|
  page.driver.browser.basic_authorize(username, password)
  
  visit "/organisation.json"
end

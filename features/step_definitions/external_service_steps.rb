Given /^the following external services:$/ do |external_services|
  set_ldap_admin_connection
  ExternalService.create!(external_services.hashes)
end

When /^I delete the (\d+)(?:st|nd|rd|th) external service$/ do |pos|
  visit external_services_path
  within("table tr:nth-child(#{pos.to_i+1})") do
    click_link "Destroy"
  end
end

Then /^I should see the following external services:$/ do |expected_external_services_table|
  expected_external_services_table.diff!( tableish('table tr', 'td,th').map{ |a| a[0..1] } )
end

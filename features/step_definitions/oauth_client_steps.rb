Given /^the following oauth client:$/ do |oauth_client|
  set_ldap_admin_connection
  OauthClient.create!(oauth_client.hashes)
end

When /^I delete the (\d+)(?:st|nd|rd|th) oauth client$/ do |pos|
  visit oauth_clients_path
  within("table tr:nth-child(#{pos.to_i+1})") do
    click_link "Remove"
  end
end

Then /^I should see the following oauth clients:$/ do |expected_oauth_clients_table|
  expected_oauth_clients_table.diff!( tableish('table tr', 'td,th').map{ |a| a[0..1] } )
end

Given /^the following devices:$/ do |devices|
  Device.create!(devices.hashes)
end

When /^I delete the (\d+)(?:st|nd|rd|th) device$/ do |pos|
  visit devices_path
  within("table tr:nth-child(#{pos.to_i+1})") do
    click_link "Destroy"
  end
end

Then /^I should see the following devices:$/ do |expected_devices_table|
  expected_devices_table.diff!(tableish('table tr', 'td,th'))
end

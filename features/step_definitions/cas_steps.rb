Given /^the following cas:$/ do |cas|
  Cas.create!(cas.hashes)
end

When /^I delete the (\d+)(?:st|nd|rd|th) cas$/ do |pos|
  visit cas_url
  within("table > tr:nth-child(#{pos.to_i+1})") do
    click_link "Destroy"
  end
end

Then /^I should see the following cas:$/ do |expected_cas_table|
  expected_cas_table.diff!(table_at('table').to_a)
end

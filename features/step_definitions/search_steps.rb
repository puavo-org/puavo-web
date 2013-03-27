Then /^I should see the following search results:$/ do |expected_table|
  rows = find('table').all('tr')
  table = rows.map { |r| r.all('th,td').map { |c| c.text.strip } }
  expected_table.diff!(table)
end

When /^I search user with "([^\"]*)"$/ do |words|
  visit search_index_path(:words => words)
end

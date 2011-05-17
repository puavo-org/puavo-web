Then /^I should see the following search results:$/ do |table|
  table.diff!(tableish('table tr', 'td,th'))
end

When /^I search user with "([^\"]*)"$/ do |words|
  visit search_index_path(:words => words)
end

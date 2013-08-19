Then /^I should see the following search results:$/ do |expected_table|
  rows = find('table').all('tr')
  table = rows.map { |r| r.all('th,td').map { |c| c.text.strip } }
  expected_table.diff!(table)
end

Then /^I should get no search results$/ do
  # TODO: Might not be the best possible implementation...
  begin
    search_res = find('table')
    raise "Unexpexted search results: #{ search_res.inspect }"
  rescue Capybara::ElementNotFound
  end
end

When /^I search user with "([^\"]*)"$/ do |words|
  visit search_index_path(:words => words)
end

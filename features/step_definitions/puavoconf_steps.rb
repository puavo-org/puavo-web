Then(/^I should see the following puavo-conf values:$/) do |puavoconf_table|
  rows = find('table#puavoconf').all('tr')
  table = rows.map { |r| r.all('th,td').map { |c| c.text.strip } }
  puavoconf_table.diff!(table)
end

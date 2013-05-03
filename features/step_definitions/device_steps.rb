When /^I enter puavo server into process "([^\"]*)"$/ do |name|
  name ||= "default"
  input = "http://#{ Capybara.current_session.server.host }:#{ Capybara.current_session.server.port }"
  @greenletters_process_table[name] << greenletters_prepare_entry(input)
end

When /^I enter puavo server into process "([^\"]*)"$/ do |name|
  name ||= "default"
  input = "http://#{ Capybara.current_session.server.host }:#{ Capybara.current_session.server.port }"
  @greenletters_process_table[name] << greenletters_prepare_entry(input)
end

Before('@start_test_server') do
  Puavo.start_test_server = true
  WebMock.disable!
end

Given /^the following devices:$/ do |servers|
  set_ldap_admin_connection
  servers.hashes.each do |attrs|
    d = Device.new
    d.classes = ["top", "device", "puppetClient", "puavoNetbootDevice"]
    d.puavoSchool = @school.dn
    d.attributes = attrs
    d.save!
  end
end

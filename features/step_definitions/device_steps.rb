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

Given('I am on the show page of device {string}') do |hostname|
end

Then('the primary user of the device {string} should be {string}') do |hostname, username|
  set_ldap_admin_connection
  d = Device.find_by_hostname(hostname)
  u = User.find(:first, :attribute => 'uid', :value => username)
  d.puavoDevicePrimaryUser.to_s.should == u.dn.to_s
end

Then('the primary user of the device {string} should be nil') do |hostname|
  set_ldap_admin_connection
  d = Device.find_by_hostname(hostname)
  d.puavoDevicePrimaryUser.should == nil
end

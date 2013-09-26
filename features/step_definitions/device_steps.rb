When /^I enter puavo server into process "([^\"]*)"$/ do |name|
  name ||= "default"
  input = "http://#{ Capybara.current_session.server.host }:#{ Capybara.current_session.server.port }"
  @greenletters_process_table[name] << greenletters_prepare_entry(input)
end

Before('@start_test_server') do
  Puavo.start_test_server = true
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

Given /^the following bootserver:$/ do |servers|
  set_ldap_admin_connection
  if @bootserver
    raise "Can add only one bootserver!"
  end
  attrs = servers.hashes.first
  school = nil
  if attrs["school"]
    school = School.find(:first, :attribute => "displayName", :value => attrs["school"])
    attrs.delete("school")
  end

  server = Server.new
  server.attributes = attrs
  server.puavoSchool = school.dn
  server.puavoDeviceType = "bootserver"
  server.save!
  @bootserver = server
end


Given /^the following printers:$/ do |servers|
  set_ldap_admin_connection

  if @bootserver.nil?
    raise "Cannot add printers before bootserver is added"
  end

  servers.hashes.each do |attrs|
    d = Printer.new
    d.attributes = attrs
    d.puavoServer = @bootserver.dn
    d.save!
  end
end

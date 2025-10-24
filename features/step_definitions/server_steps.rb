Given(/^the following servers:$/) do |servers|
  set_ldap_admin_connection
  servers.hashes.each do |attrs|
    server = Server.new
    server.attributes = attrs
    server.puavoDeviceType = 'bootserver'
    server.save!
  end
end

Given /^the following bootserver:$/ do |servers|
  set_ldap_admin_connection
  servers.hashes.each do |attrs|
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
  end
end

Given /^the following servers:$/ do |servers|
  set_ldap_admin_connection
  servers.hashes.each do |attrs|
    server = Server.new
    server.attributes = attrs
    server.puavoDeviceType = "ltspserver"
    server.save!
  end
end

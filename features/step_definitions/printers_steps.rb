
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

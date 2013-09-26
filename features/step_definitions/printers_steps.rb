
Given /^the following printers for "([^\"]*)" bootserver:$/ do |bootserver, printers|
  set_ldap_admin_connection

  bootserver = Server.find(:first,
                           :attribute => "puavoHostname",
                           :value => bootserver)
  if bootserver.nil?
    raise "Cannot add printers before bootserver is added"
  end

  printers.hashes.each do |attrs|
    d = Printer.new
    d.attributes = attrs
    d.puavoServer = bootserver.dn
    d.save!
  end
end

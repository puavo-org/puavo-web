
module PuavoRest

class PrinterQueue < LdapHash

  ldap_map :dn, :dn
  ldap_map :puavoServer, :server
  ldap_map :printerMakeAndModel, :model
  ldap_map :printerLocation, :location
  ldap_map :printerType, :type
  ldap_map :printerDescription, :description
  ldap_map :printerURI, :uri
  # TODO: as link maybe?
  # ldap_map :puavoPrinterPPD, :pdd

  def self.ldap_base
    "ou=Printers,#{ organisation["base"] }"
  end


  def self.by_server(server_dn)
    filter("(puavoServer=#{ escape server_dn })")
  end
end

class PrinterQueues < LdapSinatra


  get "/v3/printer_queues" do
    auth :basic_auth
    if params["server"]
      json PrinterQueue.by_server(params["server"])
    else
      json PrinterQueue.all
    end
  end

end

end

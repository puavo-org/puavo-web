module PuavoRest

class PrinterQueue < LdapModel

  ldap_map :dn, :dn
  ldap_map :printerMakeAndModel, :model
  ldap_map :printerLocation, :location
  ldap_map :printerType, :type
  ldap_map :printerURI, :local_uri
  ldap_map :printerDescription, :description
  ldap_map :printerDescription, :name
  ldap_map(:puavoServer, :server_fqdn) do |dn|
    BootServer.by_dn(Array(dn).first)["hostname"] + "." +  LdapModel.organisation["domain"]
  end

  def remote_uri
    "ipp://#{ server_fqdn }/printers/#{ name }"
  end

  def self.ldap_base
    "ou=Printers,#{ organisation["base"] }"
  end

  def to_hash
    o = super
    o["remote_uri"] = remote_uri
    o
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

module PuavoRest

class PrinterQueue < LdapModel

  ldap_map :dn, :dn
  ldap_map :printerMakeAndModel, :model
  ldap_map :printerLocation, :location
  ldap_map :printerType, :type
  ldap_map :printerURI, :local_uri
  ldap_map :printerDescription, :description
  ldap_map :printerDescription, :name
  ldap_map :puavoServer, :server_dn
  ldap_map :puavoPrinterPPD, :ppd

  computed_attr :server_fqdn
  def server_fqdn
    if s = server
      s.hostname + "." +  LdapModel.organisation["domain"]
    end
  end

  # Do not add pdd file contents to json presentation. Only a link to it.
  skip_serialize :ppd
  computed_attr :ppd_link
  def ppd_link
    link "/v3/printer_queues/#{ name }/ppd"
  end

  def server
    return @server if @server
    return if server_dn.nil?
    begin
      @server = BootServer.by_dn!(server_dn)
    rescue NotFound
    end
  end

  computed_attr :remote_uri
  def remote_uri
    "ipp://#{ server_fqdn }/printers/#{ name }"
  end

  def self.ldap_base
    "ou=Printers,#{ organisation["base"] }"
  end

  def self.by_server!(server_dn)
    by_attr!(:server_dn, server_dn, :multi)
  end

  def self.by_server(server_dn)
    by_attr(:server_dn, server_dn, :multi)
  end

  def self.by_name!(name)
    by_attr!(:name, name)
  end

end

class PrinterQueues < PuavoSinatra


  get "/v3/printer_queues" do
    auth :basic_auth
    if params["server_dn"]
      json PrinterQueue.by_server(params["server_dn"])
    else
      json PrinterQueue.all
    end
  end

  get "/v3/printer_queues/:name/ppd" do
    content_type 'application/octet-stream'
    auth :basic_auth
    PrinterQueue.by_name!(params["name"]).ppd
  end

end

end

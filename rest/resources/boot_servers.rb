
module PuavoRest
class BootServer < LdapModel

  ldap_map :dn, :dn
  ldap_map :puavoHostname, :hostname
  ldap_map(:puavoSchool, :school_dns) { |s| s }

  def self.ldap_base
    "ou=Servers,ou=Hosts,#{ organisation["base"] }"
  end

  # Bootservers are saved to same ldap branch as ltsp servers so we must filter
  # with type too
  def self.base_filter
    "(puavoDeviceType=bootserver)"
  end

  def self.by_hostname(hostname)
    by_attr(:hostname, hostname)
  end

  def self.by_hostname!(hostname)
    by_attr!(:hostname, hostname)
  end

  def schools
    self["school_dns"].map do |school_dn|
      School.by_dn(school_dn)
    end
  end

end

class BootServers < LdapSinatra

  get "/v3/boot_servers" do
    auth :basic_auth, :server_auth
    json BootServer.all
  end

  get "/v3/boot_servers/:hostname" do
    auth :basic_auth, :server_auth
    json BootServer.by_hostname!(params["hostname"])
  end

  get "/v3/boot_servers/:hostname/wireless_printer_queues" do
    auth :basic_auth, :server_auth

    server = BootServer.by_hostname!(params["hostname"])
    printer_queues = []
    server.schools.each do |school|
      printer_queues += school.wireless_printer_queues
    end
    json printer_queues.uniq { |printer_queue| printer_queue.name }
  end

end
end

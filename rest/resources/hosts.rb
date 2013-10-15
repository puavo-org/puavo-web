require_relative "../lib/error_codes"

module PuavoRest
class Host < LdapModel

  ldap_map :dn, :dn
  ldap_map :puavoDeviceType, :type
  ldap_map :macAddress, :mac_address
  ldap_map :puavoId, :puavo_id


  def self.ldap_base
    "ou=Hosts,#{ organisation["base"] }"
  end

  # Find host by it's mac address
  def self.by_mac_address(mac_address)
    host = filter("(macAddress=#{ escape mac_address })").first
    if host.nil?
      raise NotFound, :user => "Cannot find host with mac address '#{ mac address }'"
    end
    host
  end

end
end

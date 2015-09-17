require_relative "../../rest/resources/id_pool"

class SambaDomain < LdapBase
  ldap_mapping( :dn_attribute => "sambaDomainName",
                :prefix => "",
                :classes => ['top', 'sambaDomain'] )

  def self.next_samba_sid
    samba_domain = first
    if samba_domain.nil?
      raise "Cannot find samba domain. Organisation missing?"
    end
    res = LdapOrganisation.current.rest_proxy.post("/v3/samba_generate_next_rid")
    rid = res.parse["next_rid"]
    return "#{samba_domain.sambaSID}-#{rid}"
  end
end

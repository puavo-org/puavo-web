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

    legacy_rid = samba_domain.sambaNextRid
    pool_key = "puavoNextSambaSID:#{ samba_domain.sambaDomainName }"
    if PuavoRest::IdPool.last_id(pool_key).nil?
      PuavoRest::IdPool.set_id!(pool_key, legacy_rid)
    end

    rid = PuavoRest::IdPool.next_id(pool_key)
    samba_domain.sambaNextRid = rid
    samba_domain.save
    return "#{samba_domain.sambaSID}-#{rid - 1}"
  end
end

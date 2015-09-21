
module PuavoRest

class SambaDomain < LdapModel


  ldap_map :dn, :dn
  ldap_map :puavoId, :id
  ldap_map :sambaSID, :sid
  ldap_map :sambaDomainName, :domain
  ldap_map :sambaNextRid, :next_rid, LdapConverters::Number

  def self.ldap_base
    organisation["base"]
  end

  def self.base_filter
    "(objectClass=sambaDomain)"
  end

  # Return the Samba domain for the current organisation
  #
  # @return SambaDomain
  def self.current_samba_domain
    all_samba_domains = SambaDomain.all

    if all_samba_domains.empty?
      raise InternalError, :user => "Cannot find samba domain"
    end

   # Each organisation should have only one
    if all_samba_domains.size > 1
      raise InternalError, :user => "Too many Samba domains"
    end

    return all_samba_domains.first
  end

  # Samba rid must be in LDAP because some Windows tools can add devices
  # directly to our directory and they must be able to update the rid by
  # themselves
  #
  # @return Fixnum
  def generate_next_rid!
    lock_key = "samba_next_rid:#{ domain }"

    # Incrementing LDAP attributes with separate read and write requests is
    # prone to race conditions. Use shared Redis lock to avoid those. However
    # updating the attribute with the Windows tool mentioned above will still
    # suffer from the same issue. Unfortunately there is no easy way to fix
    # that. Lets just hope that the tool is used only by one person per
    # organisation at once.
    DISTRIBUTED_LOCK.lock(lock_key, 1000) do |locked|
      if !locked
        raise InternalError, :user => "Failed to get lock"
      end
      current_rid = next_rid

      #######################################################
      # XXX Temporary fix
      pool_key = "puavoNextSambaSID:#{ domain }"
      redis_rid = (IdPool.last_id(pool_key) || 0).to_i
      current_rid = [redis_rid, current_rid].max()
      #######################################################

      self.next_rid = current_rid + 1
      save!

      return current_rid
    end
  end

end

class SambaNextRid < PuavoSinatra
  get "/v3/samba_current_rid" do
    auth :basic_auth
    json({"current_rid" => SambaDomain.current_samba_domain.next_rid})
  end

  post "/v3/samba_generate_next_rid" do
    auth :basic_auth
    json({"next_rid" => SambaDomain.current_samba_domain.generate_next_rid!})
  end
end

end

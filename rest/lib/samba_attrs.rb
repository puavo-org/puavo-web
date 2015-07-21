module PuavoRest

  module SambaAttrs

    def set_samba_primary_group_sid(school_id)
      write_raw(:sambaPrimaryGroupSID, ["#{samba_domain.sid}-#{school.id}"])
    end

    def set_samba_sid
      rid = next_rid("puavoNextSambaSID")
      write_raw(:sambaSID, ["#{ samba_domain.sid }-#{ rid - 1}"])

    end

    private

    def next_rid(key)
      pool_key = "#{pool_key}:#{ samba_domain.domain }"

      if IdPool.last_id(pool_key).nil?
        IdPool.set_id!(pool_key, samba_domain.legacy_rid)
      end

      return IdPool.next_id(pool_key)
    end

    def samba_domain
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

  end
end

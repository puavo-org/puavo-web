module PuavoRest

  module SambaAttrs

    def set_samba_primary_group_sid(school_id)
      write_raw(:sambaPrimaryGroupSID, ["#{samba_domain.sid}-#{school.id}"])
    end

    def set_samba_sid
      rid = samba_domain.generate_next_rid!

      write_raw(:sambaSID, ["#{ samba_domain.sid }-#{ rid - 1}"])

      samba_sid = Array(get_raw(:sambaSID)).first
      if samba_sid && new?
        res = LdapModel.raw_filter(organisation["base"], "(sambaSID=#{ escape samba_sid })")
        if res && !res.empty?
          other_dn = res.first["dn"].first
          # Internal attribute, use underscore prefix to indicate that
          add_validation_error(:__sambaSID, :sambaSID_not_unique, "#{ samba_sid } is already used by #{ other_dn }")
        end
      end

      # Redo validation for samba attrs
      assert_validation

    end

    private

    # Cached samba domain query
    def samba_domain
      return @samba_domain if @samba_domain

      all_samba_domains = SambaDomain.all

      if all_samba_domains.empty?
        raise InternalError, :user => "Cannot find samba domain"
      end

      # Each organisation should have only one
      if all_samba_domains.size > 1
        raise InternalError, :user => "Too many Samba domains"
      end

      @samba_domain = all_samba_domains.first
    end

  end
end

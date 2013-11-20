
# generic ldap search rutines
class LdapModel

  # LDAP base for this model. Must be implemented by subclasses

  def self.ldap_base
    raise "ldap_base is not implemented for #{ self.name }"
  end

  # LDAP::LDAP_SCOPE_SUBTREE filter search for #ldap_base
  #
  # @param filter [String] LDAP filter
  # @param attributes [Array] Limit search results to these attributes
  # @see http://ruby-ldap.sourceforge.net/rdoc/classes/LDAP/Conn.html#M000025
  # @return [Array]
  def self.raw_filter(filter, attributes=nil)
    res = []
    attributes ||= ldap_attrs

    if not connection
      raise "Cannot search without a connection"
    end

    connection.search(
      ldap_base,
      LDAP::LDAP_SCOPE_SUBTREE,
      filter,
      attributes.map{ |a| a.to_s }
    ) do |entry|
      res.push(entry.to_hash) if entry.dn != ldap_base
    end

    res
  end

  # Return convert values to LdapHashes before returning
  # @see raw_filter
  def self.filter(*args)
    raw_filter(*args).map! do |entry|
      from_hash(entry)
    end
  end


  def self.by_ldap_attr(attr, value, option=nil)
    res = Array(filter("(#{ escape attr }=#{ escape value })"))
    return if res.empty?
    if option == :multi
      res
    else
      res.first
    end
  end

  def self.by_ldap_attr!(attr, value, option=nil)
     res = by_ldap_attr(attr, value, option)
     if res.nil?
      raise(
        NotFound,
        :user => "Cannot find #{ self.class } by #{ attr }=#{ val }"
      )
     end
     res
  end

  # Find model by it's mapped attribute. It's safe to call with user input
  # since the value is escaped before ldap search.
  #
  # @param attr [Symbol] Mapped attribute
  # @param value [String] Attribute value to match
  # @param option [Symbol] Set to :multi to return an Array
  # @return [LdapModel]
  def self.by_attr(attr, value, option=nil)
    by_ldap_attr(pretty2ldap[attr.to_sym], value, option)
  end

  # Same as by_attr but it will throw NotFound exception if the value is nil
  def self.by_attr!(attr, value, option=nil)
    by_ldap_attr!(pretty2ldap[attr.to_sym], value, option)
  end

  # Return all ldap entries from the current base
  #
  # @see ldap_base
  def self.all
    filter("(objectClass=*)")
  end

  # Find any ldap entry by dn
  #
  # @param dn [String]
  # @param attributes [Array of Strings]
  def self.raw_by_dn(dn, attributes=nil)
    res = nil
    attributes ||= ldap_attrs.map{ |a| a.to_s }

    connection.search(
      dn,
      LDAP::LDAP_SCOPE_SUBTREE,
      "(objectclass=*)",
      attributes
    ) do |entry|
      res = entry.to_hash
      break
    end

    res
  end

  # Return convert value to LdapHashes before returning
  # @see raw_by_dn
  def self.by_dn(*args)
    from_hash( raw_by_dn(*args) )
  end

  # Get array of models by their dn attributes.
  #
  # Nonexistent DNs are ignored.
  def self.by_dn_array(dns)
    Array(dns).map do |dn|
      begin
        by_dn(dn)
      rescue LDAP::ResultError
        # Ignore broken dn pointers
      end
    end.compact
  end

end

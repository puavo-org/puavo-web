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

    timer = PROF.start

    connection.search(
      ldap_base,
      LDAP::LDAP_SCOPE_SUBTREE,
      filter,
      attributes.map{ |a| a.to_s }
    ) do |entry|
      res.push(entry.to_hash) if entry.dn != ldap_base
    end

    timer.stop("#{ self.name }#filter(#{ filter.inspect }) #{ attributes.inspect } found #{ res.size } items")
    PROF.count(timer)

    res
  end

  # Return convert values to LdapHashes before returning
  # @see raw_filter
  def self.filter(_filter, attrs=nil)
    ldap_attributes = nil
    pretty_attributes = nil

    if attrs.class == String
      attrs = attrs.split(",").map{|s| s.strip }
    end

    if attrs
      ldap_attributes = attrs.map{|a| pretty2ldap[a.to_sym]}.compact
    end

    raw_filter(_filter, ldap_attributes).map! do |entry|
      from_ldap_hash(entry, attrs)
    end
  end


  def self.by_ldap_attr(attr, value, option=nil, attrs=nil)
    custom_filter = "(#{ escape attr }=#{ escape value })"
    full_filter = "(&#{ base_filter }#{ custom_filter })"

    res = Array(filter(full_filter, attrs))
    if option == :multi
      res
    else
      res.first
    end
  end

  def self.by_ldap_attr!(attr, value, option=nil, attrs=nil)
     res = by_ldap_attr(attr, value, option, attrs)
     if Array(res).empty?
      raise(
        NotFound,
        "Cannot find #{ self } by #{ attr }=#{ value }"
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
  def self.by_attr(attr, value, option=nil, attrs=nil)
    ldap_attr = pretty2ldap[attr.to_sym]

    if ldap_attr.nil?
      # Would compile to invalid ldap search filter. Throw early with human
      # readable error message
      raise "Invalid pretty attribute #{ attr } for #{ self }"
    end

    by_ldap_attr(ldap_attr, value, option, attrs)
  end

  # Same as by_attr but it will throw NotFound exception if the value is nil
  def self.by_attr!(attr, value, option=nil, attrs=nil)
    by_ldap_attr!(pretty2ldap[attr.to_sym], value, option, attrs)
  end

  # Return all ldap entries from the current base
  #
  # @see ldap_base
  def self.all(attrs=nil)
    filter(base_filter, attrs)
  end

  # Find any ldap entry by dn
  #
  # @param dn [String]
  # @param attributes [Array of Strings]
  def self.raw_by_dn(dn, attributes=nil)
    res = nil
    attributes ||= ldap_attrs.map{ |a| a.to_s }

    timer = PROF.start

    if connection.nil?
      raise "Connection is not setup!"
    end

    connection.search(
      dn,
      LDAP::LDAP_SCOPE_BASE,
      "(objectclass=*)",
      attributes
    ) do |entry|
      res = entry.to_hash
      break
    end

    timer.stop("#{ self.name }#by_dn(#{ dn.inspect }) found #{ res.size } items")
    PROF.count(timer)

    res
  end

  # When filtering models with `LdapModel#filter(...)` this filter will be
  # added to it automatically with AND operator (&). Usefull when there are
  # multiple LdapModel is the same LDAP branch.
  #
  # Override this in subclasses when needed.
  def self.base_filter
    "(objectclass=*)"
  end

  # Return convert value to LdapHashes before returning
  # @see raw_by_dn
  def self.by_dn(*args)
    from_ldap_hash( raw_by_dn(*args) )
  end

  def self.by_dn!(*args)
    res = by_dn(*args)
    if not res
      raise NotFound, :user => "Cannot find #{ self.class } by dn: #{ args.first.inspect }"
    end
    res
  end

  # Get array of models by their dn attributes.
  #
  # Nonexistent DNs are ignored.
  def self.by_dn_array(dns)
    timer = PROF.start

    res = Array(dns).map do |dn|
      begin
        by_dn(dn)
      rescue LDAP::ResultError
        # Ignore broken dn pointers
      end
    end.compact

    timer.stop("#{ self.name }#by_dn_array(<with #{ dns.size } items>)")

    res
  end

  def self.search_filters
    raise "search_filters not implemented for #{ self }"
  end

  # Search for models using keywords
  #
  # `keywords` can be a string of `+` or space separated keywords or an array
  # of keywords. Those models are returned which have a match for all the
  # keywords.
  #
  # Each model using this method must implement a `search_filters` method which
  # returns an array of lambdas which generate the approciate ldap search
  # filters. See create_filter_lambda
  def self.search(keywords)
    if keywords.kind_of?(String)
      keywords = keywords.gsub("+", " ").split(" ")
    end

    return [] if keywords.nil?
    return [] if keywords.empty?

    filter_string = "(&" + keywords.map do |keyword|
      "(|" + search_filters.map do |sf|
        sf.call(keyword)
      end.join("") + ")"
    end.join("") + ")"

    filter(filter_string)
  end

  # Return a lambda which converts ldap field value to ldap search filter
  #
  # Example:
  #
  #   l = create_filter_lambda(:username) { |value| "*#{ v }*" }
  #   filter = l.call("foo")
  #   "(uid=*foo*)"
  #
  def self.create_filter_lambda(pretty_attr, &convert)
    if convert.nil?
      convert = lambda { |v| "*#{ v }*" }
    end

    ldap_attr = pretty2ldap[pretty_attr.to_sym]
    raise "Unknown pretty attribute '#{ pretty_attr }' for #{ self }" if not ldap_attr
    lambda { |keyword| "(#{ ldap_attr }=#{ convert.call(escape(keyword)) })" }
  end

end

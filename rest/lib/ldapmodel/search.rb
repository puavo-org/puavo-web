# generic ldap search rutines
class LdapModel

  # LDAP base for this model. Must be implemented by subclasses

  # Override in a subclass
  # @return String
  def self.ldap_base
    raise "ldap_base is not implemented for #{ self.name }"
  end

  # LDAP::LDAP_SCOPE_SUBTREE filter search for #ldap_base
  #
  # @param base [String] LDAP base
  # @param filter [String] LDAP filter
  # @param attributes [Array] Limit search results and return values to these attributes
  # @see http://ruby-ldap.sourceforge.net/rdoc/classes/LDAP/Conn.html#M000025
  # @return [Array]
  def self.raw_filter(base, filter, attributes=nil, &block)
    res = []
    attributes ||= ldap_attrs

    if not connection
      raise "Cannot search without a connection"
    end

    timer = PROF.start

    if block.nil?
      block = lambda do |entry|
        res.push(entry.to_hash) if entry.dn != base
      end
    end

    begin
      ldap_op(
        :search,
        base,
        LDAP::LDAP_SCOPE_SUBTREE,
        filter,
        attributes.map{ |a| a.to_s },
        &block
      )
    ensure
      timer.stop("#{ self.name }#raw_filter(#{ filter.inspect }) base:#{ base } attributes:#{ attributes.inspect } found #{ res.size } items")
      PROF.count(timer)
    end


    res
  end

  # Convert array of pretty names to ldap attribute names
  # @param [Array<Symbol>] attrs
  def self.pretty_attrs_to_ldap(attrs=nil)
    if attrs
      attrs = attrs.map{|a| pretty2ldap[a.to_sym]}.compact
    end
    attrs
  end

  # Do LDAP search with a custom filte combined with {.base_filter}.
  # {.ldap_base} will be used as the base.
  #
  # @param [String] custom_filter
  # @param [Hash] options
  # @option options [Array] :attrs Array of pretty attributes to return
  # @option options [Array] :ldap_attrs Array of ldap attributes to return
  # @option options [Boolean] :multiple Set to `true` to return Array of LdapModels instead of single one
  # @option options [Boolean] :raw Set to `true` to return raw ruby-ldap Hash
  #
  # @return [LdapModel, Array<LdapModel>]
  def self.filter(custom_filter, options={})
    _pretty_attrs = options[:attrs]
    _ldap_attrs = get_ldap_attrs(options)

    if custom_filter
      full_filter = "(&#{ base_filter }#{ custom_filter })"
    else
      full_filter = base_filter
    end

    res = Array(raw_filter(ldap_base, full_filter, _ldap_attrs).map! do |entry|
      if options[:raw]
        entry
      else
        from_ldap_hash(entry, _pretty_attrs)
      end
    end)

    if options[:multiple]
      return res
    else
      if res.size > 1
        STDERR.puts "WARNING: LDAP filter #{ full_filter } returns multiple values for base #{ ldap_base } but only one is returned"
      end
      return res.first
    end
  end


  # Filter models by a attribute.
  #
  #
  # @param [Symbol] attr LDAP name of the attribute
  # @param [Object] value
  # @param [Hash] options See {.filter}
  # @return [Array<LdapModel>, LdapModel]
  def self.by_ldap_attr(attr, value, options={})
    return filter("(#{ escape attr }=#{ escape value })", options)
  end

  # (see .by_ldap_attr)
  # Raises {NotFound} if no models were found
  def self.by_ldap_attr!(attr, value, options={})
     res = by_ldap_attr(attr, value, options)
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
  # @param pretty_name [Symbol] Mapped attribute
  # @param value [Object] Attribute value to match
  # @param [Hash] options See {.filter}
  # @return [Array<LdapModel>, LdapModel]
  def self.by_attr(pretty_name, value, options={})
    by_ldap_attr(pretty2ldap!(pretty_name), value, options)
  end

  # (see .by_attr)
  #
  # Raises {NotFound} if no models were found
  def self.by_attr!(attr, value, options={})
    by_ldap_attr!(pretty2ldap!(attr), value, options)
  end

  # Find model by `id` attribute.
  #
  # @see .by_attr
  # @return LdapModel
  def self.by_id(id, options={})
    by_attr(:id, id, options)
  end

  # (see .by_id)
  #
  # Raises {NotFound} if no models were found.
  def self.by_id!(id, options={})
    by_attr!(:id, id, options)
  end

  # Return all ldap entries from the current base
  #
  # @see ldap_base
  def self.all(options={})
    filter(nil, options.merge(:multiple => true))
  end

  # Find any ldap entry by dn
  #
  # @param dn [String]
  # @param [Hash] options
  # @option options [Array] :attrs Array of pretty attributes to return
  # @option options [Array] :ldap_attrs Array of ldap attributes to return
  def self.raw_by_dn(dn, options={})
    attributes = get_ldap_attrs(options)

    timer = PROF.start

    if connection.nil?
      raise "Connection is not setup!"
    end

    res = nil
    raw_filter(dn, "(objectclass=*)", attributes) do |entry|
      res = entry.to_hash
      break
    end
    res
  end

  # When filtering models with {.filter} this filter will be
  # added to it automatically with AND operator (&). Usefull when there are
  # multiple LdapModels is the same LDAP branch / base.
  #
  # Override this in subclasses when needed.
  # @return String
  def self.base_filter
    "(objectclass=*)"
  end

  # Find model by `dn` attribute.
  #
  # @see .raw_by_dn
  # @param dn [String] dn string
  # @param options [Hash] See {.raw_by_dn}
  # @return LdapModel
  def self.by_dn(dn, options={})
    res = raw_by_dn(dn, options)
    from_ldap_hash(res) if res
  end

  # (see .by_dn)
  #
  # Raises {NotFound} if no models were found
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
  #
  # @param dns [Array<String>] array of dn string
  # @return Array<LdapModel>
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

  # @see .search
  # @return [Array<Proc>]
  def self.search_filters
    raise "search_filters not implemented for #{ self }"
  end

  # Search for models using keywords
  #
  # `keywords` can be a string of `+` or space separated keywords or an array
  # of keywords. Those models are returned which have a match for all the
  # keywords.
  #
  # Each model using this method must implement a {.search_filters} method which
  # returns an array of lambdas (Proc) which generate the approciate ldap search
  # filters. See {.create_filter_lambda}
  # @param keywords [Symbol] String of search keywords
  # @param options [Hash] See {.filter}
  # @return Array<LdapModel>
  def self.search(keywords, options={})
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

    filter(filter_string, options.merge(:multiple => true))
  end

  # Return a lambda which converts ldap field value to ldap search filter
  #
  # Example:
  #
  #     l = create_filter_lambda(:username) { |value| "*#{ v }*" }
  #     filter = l.call("foo")
  #     "(uid=*foo*)"
  #
  # @param pretty_attr [Symbol]
  # @param &convert [Block]
  # @return [Proc]
  def self.create_filter_lambda(pretty_attr, &convert)
    if convert.nil?
      convert = lambda { |v| "*#{ v }*" }
    end

    ldap_attr = pretty2ldap[pretty_attr.to_sym]
    raise "Unknown pretty attribute '#{ pretty_attr }' for #{ self }" if not ldap_attr
    lambda { |keyword| "(#{ ldap_attr }=#{ convert.call(escape(keyword)) })" }
  end

  private

  def self.get_ldap_attrs(options={})
    _ldap_attrs = pretty_attrs_to_ldap(options[:attrs]) || []
    _ldap_attrs += Array(options[:ldap_attrs])
    _ldap_attrs.uniq!
    _ldap_attrs
  end


end

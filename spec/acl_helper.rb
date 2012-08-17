
# net-ldap based OpenLDAP ACL testing helper for RSPEC

def acl_user(dn, password)
  a = ACLTester.new(@ldap_host, dn.to_s, password)
  yield a
  a
end

class ACLViolation < Exception
end

class ACLTester

  def initialize(ldap_host, dn, password)
    @ldap_host = ldap_host
    @dn = dn
    @password = password
    connect
  end


  def can_read(target_dn, attributes=nil)
    attributes = [attributes] if attributes.class != Array

    entry = @conn.search(:base => target_dn.to_s)

    if entry.size == 0
      raise ACLViolation, "Failed to read #{ target_dn.to_s } from #{ @ldap_host }"
    end

    attributes.each do |attr|
      if entry.first[attr].size == 0
        raise ACLViolation, "Failed to read attribute '#{ attr }' from #{ target_dn.to_s  } in #{ @ldap_host }"
      end
    end

    return entry
  end

  def can_modify(target_dn, ops)
    # http://net-ldap.rubyforge.org/Net/LDAP.html#method-i-modify
    @conn.modify :dn => target_dn.to_s, :operations => ops
    res = @conn.get_operation_result()
    if res.code != 0
      raise ACLViolation, "Failed to modify '#{ target_dn.to_s }' as '#{ @dn }'. Message: #{ res.message }"
    end
    return res
  end

  private

  def connect
    @conn = Net::LDAP.new(
      :host => @ldap_host,
      :port => 389,
      :encryption => {
        :method => :start_tls
      },
      :auth => {
        :method => :simple,
        :username => @dn,
        :password => @password
    })

    if not @conn.bind
      raise ACLViolation, "Cannot bind #{ @dn } : #{ @password } to #{ @ldap_host }"
    end

  end

end


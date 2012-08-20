

# before(:all) block
# Usage: before :each, &reset_ldap
def reset_ldap
  lambda do
    test_organisation = Puavo::Organisation.find('example')
    default_ldap_configuration = ActiveLdap::Base.ensure_configuration
    # Setting up ldap configuration
    @ldap_host = test_organisation.ldap_host
    @ldap_base = test_organisation.ldap_base
    LdapBase.ldap_setup_connection( test_organisation.ldap_host,
                                    test_organisation.ldap_base,
                                    default_ldap_configuration["bind_dn"],
                                    default_ldap_configuration["password"] )



    # Clean Up LDAP server: destroy all schools, groups and users
    User.all.each do |u|
      unless u.uid == "cucumber"
        u.destroy
      end
    end
    Group.all.each do |g|
      unless g.displayName == "Maintenance"
        g.destroy
      end
    end
    School.all.each do |s|
      unless s.displayName == "Administration"
        s.destroy
      end
    end
    Role.all.each do |p|
      unless p.displayName == "Maintenance"
        p.destroy
      end
    end
  end
end


# net-ldap based OpenLDAP ACL testing helper for RSPEC

def as_user(dn, password)
  a = ACLTester.new(@ldap_host, dn.to_s, password)
  a.connect
  yield a
  a
end



class LDAPException < Exception
end

class InsufficientAccessRights < LDAPException
end

class ConstraintViolation < LDAPException
end

class BindFailed < LDAPException
end



class ACLTester


  def initialize(ldap_host, dn, password)
    @ldap_host = ldap_host
    @dn = dn
    @password = password
  end


  def can_read(target_dn, attributes=nil)
    attributes = [attributes] if attributes.class != Array

    entry = @conn.search(:base => target_dn.to_s)

    if entry.size == 0
      raise InsufficientAccessRights, "Failed to read #{ target_dn.to_s } from #{ @ldap_host }"
    end

    attributes.each do |attr|
      if entry.first[attr].size == 0
        raise InsufficientAccessRights, "Failed to read attribute '#{ attr }' from #{ target_dn.to_s  } in #{ @ldap_host }"
      end
    end

    return entry
  end

  def can_modify(target_dn, op)

    # http://net-ldap.rubyforge.org/Net/LDAP.html#method-i-modify
    # Allow only one operation at once so that we can show clear error messages
    @conn.modify :dn => target_dn.to_s, :operations => [op]

    res = @conn.get_operation_result()
    if res.code != 0
      err_msg = "Failed to do '#{ op[0] }' on attribute '#{ op[1] }' in '#{ target_dn.to_s }' as '#{ @dn }'"

      # http://web500gw.sourceforge.net/errors.html
      if res.code == 19
        raise ConstraintViolation, err_msg
      end

      raise InsufficientAccessRights, err_msg +  ". Message: #{ res.message }"

    end
    return res
  end

  def set_password(target_dn, new_password)
    args = [
      'ldappasswd', '-x', '-Z',
      '-h', @ldap_host,
      '-D', @dn,
      '-w', @password,
      '-s', new_password,
      target_dn.to_s
    ]

    system(*args)

    if $?.exitstatus != 0
      raise LDAPException, "Failed to execute #{ args.join " " }"
    end

    pw_test = ACLTester.new(@ldap_host, target_dn, new_password)
    pw_test.connect

  end

  def connect
    @conn = Net::LDAP.new(
      :host => @ldap_host,
      :port => 389,
      :encryption => {
        :method => :start_tls
      },
      :auth => {
        :method => :simple,
        :username => @dn.to_s,
        :password => @password
    })

    if not @conn.bind
      raise InsufficientAccessRights, "Cannot bind #{ @dn } : #{ @password } to #{ @ldap_host }"
    end

  end

end

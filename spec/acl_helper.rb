require 'acl_data'

class LDAPException < Exception
end

class InsufficientAccessRights < LDAPException
end

class ConstraintViolation < LDAPException
end

class BindFailed < LDAPException
end


class LDAPTestEnv

  def initialize
    @definitions = {}
    define_basic(self)
  end

  def reset
    # Configure LDAP
    test_organisation = Puavo::Organisation.find('example')
    default_ldap_configuration = ActiveLdap::Base.ensure_configuration
    # Setting up ldap configuration
    @ldap_host = test_organisation.ldap_host
    @ldap_base = test_organisation.ldap_base
    LdapBase.ldap_setup_connection( test_organisation.ldap_host,
                                    test_organisation.ldap_base,
                                    default_ldap_configuration["bind_dn"],
                                    default_ldap_configuration["password"] )



    # Clean Up LDAP destroy all schools, groups and users
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

    @entries = {}


  end


  def define(*ids, &seeder)
    ids.each do |id|
      @definitions[id] = [ids, seeder]
    end
  end

  def method_missing(id)

    if e = @entries[id]
      # puts "Using cached #{ id }".green
      return e
    end

    definition = @definitions[id]
    if not definition
      raise "Undefined LDAP Object #{ id } (or just method missing)"
    end

    other_ids = definition[0]
    seeder = definition[1]

    entries = other_ids.map do |other_id|
      e = LDAPObject.new @ldap_host, self
      @entries[other_id] = e
      e
    end

    seeder.call(*entries)
    return @entries[id]
  end

  # def use_with(*ids)
  #   reset

  #   entries = ids.map do |id|
  #     e = @entries[id]
  #     e.connect
  #     e
  #   end
  #   yield(*entries)
  # end


end




class LDAPObject

  attr_accessor :password

  def initialize(ldap_host, env)
    @ldap_host = ldap_host
    @env = env
  end

  def ensure_object(target)
    if target.class == self.class
      return target
    end
    return @env.send target
  end

  def to_s
    @dn.to_s
  end

  def default_password
    @password = "secret"
  end

  attr_reader :dn
  def dn=(dn)
    @dn = dn.to_s
  end

  def can_read(target, attributes=nil)
    target = ensure_object(target)
    connect

    attributes = [attributes] if attributes.class != Array

    entry = @conn.search(:base => target.dn)

    if entry == false || entry.size == 0
      raise InsufficientAccessRights, "Failed to read #{ target.dn } from #{ @ldap_host }"
    end

    attributes.each do |attr|
      if entry.first[attr].size == 0
        raise InsufficientAccessRights, "Failed to read attribute '#{ attr }' from #{ target.dn  } in #{ @ldap_host }"
      end
    end

    return entry
  end

  def can_modify(target, op)
    target = ensure_object(target)
    connect

    # http://net-ldap.rubyforge.org/Net/LDAP.html#method-i-modify
    # Allow only one operation at once so that we can show clear error messages
    @conn.modify :dn => target.dn, :operations => [op]

    res = @conn.get_operation_result()
    if res.code != 0
      err_msg = "Failed to do '#{ op[0] }' on attribute '#{ op[1] }' in '#{ target.dn }' as '#{ @dn }'"

      # http://web500gw.sourceforge.net/errors.html
      if res.code == 19
        raise ConstraintViolation, err_msg
      end

      raise InsufficientAccessRights, err_msg +  ". Message: #{ res.message }"

    end
    return res
  end

  def can_set_password_for(target, foo=nil)
    target = ensure_object(target)
    connect

    new_password = "secret2"
    args = [
      'ldappasswd', '-x', '-Z',
      '-h', @ldap_host,
      '-D', @dn,
      '-w', @password,
      '-s', new_password,
      target.dn
    ]

    system(*args)

    if $?.exitstatus != 0
      raise LDAPException, "Failed to execute #{ args.join " " }"
    end

    pw_test = LDAPObject.new(@ldap_host, @env)
    pw_test.dn = target.dn
    pw_test.password = new_password
    pw_test.connect

  end

  def connect
    return if @connected
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
      raise BindFailed, "Cannot bind #{ @dn } : #{ @password } to #{ @ldap_host }"
    end

    @connected = true
  end

end




require "colorize"

class LDAPTestEnvException < Exception
end

class InsufficientAccessRights < LDAPTestEnvException
end

class ConstraintViolation < LDAPTestEnvException
end

class BindFailed < LDAPTestEnvException
end

class ExpectationError < LDAPTestEnvException
end


class LDAPTestEnv
  @@test_count = 0

  def initialize
    define_basic(self)
  end

  # Disable all testing for this env
  def disable
    @disabled = true
  end

  def self.report
    puts "#{ @@test_count } tests ok".green
  end

  def inc_test_count
    @@test_count += 1
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
    id_pool = IdPool.find('IdPool')
    id_pool.puavoNextGidNumber = 10004
    id_pool.puavoNextUidNumber = 10002
    id_pool.puavoNextRid = 3
    id_pool.puavoNextId = 9
    id_pool.save!

    @entries = {}


  end

  def validate(name, &block)

    if @disabled
      puts "Skipping '#{ name }' because it is disabled".red
      return
    end

    puts "### #{ name } ACLs ###".yellow
    reset
    instance_eval(&block)
  end

  # Define test data object.
  def define(*ids, &seeder)
    ids.each do |id|

      # Define lazy method that creates and returns the ldap object when called
      singleton = class << self; self end
      singleton.send :define_method, id, lambda {

        if e = @entries[id]
          return e
        end

        # Single define can create multiple ldap objects
        entries_to_be = ids.map do |other_id|
          e = LDAPObject.new id, @ldap_host, self
          @entries[other_id] = e
          e
        end

        seeder.call(*entries_to_be)
        entries_to_be.each do |e|
          if not e.dn
            raise "Definition for #{ e.id } did not set a dn!"
          end
        end
        @entries[id]
      }
    end
  end


end




class LDAPObject

  attr_accessor :password
  attr_reader :dn, :id
  @@test_count = 0

  def initialize(id, ldap_host, env)
    @id = id
    @ldap_host = ldap_host
    @env = env
    @log_prefix = ""
  end

  def ensure_object(target)
    if target.class == self.class
      return target
    end
    return @env.send target
  end

  def to_s
    # "<#{ @id }(#{ @dn })>"
    "#{ @id }"
  end

  def default_password
    @password = "secret"
  end

  def dn=(dn)
    @dn = dn.to_s
  end

  def log(msg)
    puts @log_prefix + msg
    @log_prefix = ""
    @env.inc_test_count
  end

  def self.method_added(method_name)

    # create "cannot_" versions of "can_" methods
    if method_name.to_s[0...4] == "can_"
      new_name = method_name.to_s.gsub(/can_/, "cannot_")

      define_method new_name.to_sym do |*args|
        exception = args.last
        args = args[0...-1]
        begin
          @log_prefix = "NOT: "
          send(method_name, *args)
        rescue exception
          return
        end
        raise "Expected '#{ new_name }(#{ args.join ", " })' on #{ to_s } to raise #{ exception }"
      end

    end
  end


  def can_read(target, attributes=nil)
    attributes = [attributes] if attributes.class != Array
    target = ensure_object(target)
    connect

    log "#{ to_s.blue } can read  [#{ attributes.join "|" }] from #{ target.to_s.blue }"

    raise "Invalid arguments: " + attributes.inspect if attributes.first.class == Array

    entry = @conn.search(:base => target.dn)

    if entry == false || entry.size == 0
      raise InsufficientAccessRights, "#{ to_s } failed to read anything from #{ target }"
    end

    attributes.each do |attr|
      if entry.first[attr].size == 0
        raise InsufficientAccessRights, "#{ to_s } failed to read attribute '#{ attr }' from #{ target }"
      end
    end

    return entry
  end

  def can_modify(target, op)
    target = ensure_object(target)
    connect

    log "#{ to_s.blue } can do [#{ op.join "|" }] to #{ target.to_s.blue }"
    # http://net-ldap.rubyforge.org/Net/LDAP.html#method-i-modify
    # Allow only one operation at once so that we can show clear error messages
    @conn.modify :dn => target.dn, :operations => [op]

    res = @conn.get_operation_result()
    if res.code != 0
      err_msg = "#{ to_s } failed to do '#{ op[0] }' on attribute '#{ op[1] }' in '#{ target }'"

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
    log "#{ to_s.blue } change change password for #{ target.to_s.blue }"

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
      # TODO: Add stdout&stderr to the message
      raise LDAPTestEnvException, "#{ to_s  } failed to change password for #{ target }"
    end

    pw_test = LDAPObject.new(@id, @ldap_host, @env)
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
      raise BindFailed, "#{ to_s } cannot bind with password '#{ @password }' to #{ @ldap_host }"
    end

    @connected = true
  end

end



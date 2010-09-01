require 'sha1'
require 'base64'

class Server < LdapBase
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Servers,ou=Hosts",
                :classes => ['top', 'device', 'puppetClient', 'puavoServer', 'simpleSecurityObject'] )

  has_many( :automounts, :class_name => 'Automount',
            :primary_key => 'dn',
            :foreign_key => 'puavoServer' )

  before_validation :set_puavo_id, :set_password
  before_save :set_parentNode

  def self.ssha_hash(password)
    salt = ActiveSupport::SecureRandom.base64(16)
    "{SSHA}" + Base64.encode64(Digest::SHA1.digest(password + salt) + salt).chomp!
  end

  def full_hostname
    "#{self.puavoHostname}.#{LdapOrganisation.first.puavoDomain}"
  end

  def id
    self.puavoId.to_s unless self.puavoId.nil?
  end

  def set_password
    if self.userPassword.nil? || self.userPassword.empty?
      characters = ("a".."z").to_a + ("0".."9").to_a
      self.new_password = Array.new(40) { characters[rand(characters.size)] }.join
      self.userPassword = Server.ssha_hash(self.new_password)
    end
  end

  private

  def set_puavo_id
    self.puavoId = IdPool.next_puavo_id if self.puavoId.nil?
    self.cn = self.puavoHostname
  end

  def set_parentNode
    self.parentNode = LdapOrganisation.current.puavoDomain
  end
end

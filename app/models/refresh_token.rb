class RefreshToken < LdapBase
  include Puavo::Security
  include OAuthHelpers

  LIFETIME = 6.months

  ldap_mapping( :dn_attribute => "puavoOAuthTokenId",
              :prefix => "ou=Tokens,ou=OAuth",
              :classes => ["simpleSecurityObject", "puavoOAuthRefreshToken"] )

  before_save :encrypt_userPassword

  class Expired < UserError
    attr_accessor :token
    def initialize(message, token)
      super message
      @token = token
    end
  end

  def self.validate(token)
    if self.expired? token[:created]
      rt = RefreshToken.find token[:dn]
      rt.userPassword = RefreshToken.generate_nonsense
      rt.save!
      raise Expired.new "Reresh Token Expired", token
    end
    return true
  end

  def self.find_and_validate(token)
    self.validate token
    self.find token[:dn]
  end

  def self.expired?(created)
    age = Time.now - created.to_time
    return age > LIFETIME
  end


end

require "oauth_helpers"

class AccessToken < LdapBase
  include Puavo::Security
  include OAuthHelpers

  ldap_mapping( :dn_attribute => "puavoOAuthTokenId",
                :prefix => "ou=Tokens,ou=OAuth",
                :classes => ["simpleSecurityObject", "puavoOAuthAccessToken"] )

  before_save :encrypt_userPassword

  LIFETIME = 5.days

  class Expired < UserError
    attr_accessor :token
    def initialize(message, token)
      super message
      @token = token
    end
  end


  def self.decrypt_token(raw_token)
    token = self.token_manager.decrypt raw_token
    token.symbolize_keys!
    token[:dn] = ActiveLdap::DistinguishedName.parse token[:dn]
    return token
  end

  def self.validate(token)
    if self.expired? token[:created]
      at = AccessToken.find token[:dn]
      at.userPassword = AccessToken.generate_nonsense
      at.save!
      raise Expired.new "Token expired", token
    end
  end

  def self.expired?(created)
    age = Time.now - created.to_time
    return age > LIFETIME
  end

  def encrypt_token(extra)

    # Set token id only once
    self.puavoOAuthTokenId ||= UUID.new.generate

    # Change password so the encrypted token is different each time
    access_token_password = AccessToken.generate_nonsense
    self.userPassword = access_token_password

    save!

    access_token = self.class.token_manager.encrypt({
      "dn" => dn.to_s,
      "password" => access_token_password,
      "created" => Time.now,
    }.merge!(extra))

  end

end

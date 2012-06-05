class RefreshToken < LdapBase
  include Puavo::Security
  LIFETIME = 6.months

  ldap_mapping( :dn_attribute => "puavoOAuthTokenId",
              :prefix => "ou=Tokens,ou=OAuth",
              :classes => ["simpleSecurityObject", "puavoOAuthRefreshToken"] )

  before_save :encrypt_userPassword

  class Expired < UserError
  end

  def self.decrypt_token(raw_token)
    tm = Puavo::OAuth::TokenManager.new Puavo::OAUTH_CONFIG["token_key"]
    token = tm.decrypt raw_token

    if self.expired? token["created"]
      raise Expired
    end

    token["dn"] = ActiveLdap::DistinguishedName.parse token["dn"]
    return token
  end

  def self.expired?(created)
    age = Time.now - created.to_time
    return age > LIFETIME
  end


end

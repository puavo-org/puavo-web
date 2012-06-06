
module OAuthHelpers


  module ClassMethods

    def token_manager
      tm = Puavo::OAuth::TokenManager.new Puavo::OAUTH_CONFIG["token_key"]
    end

    def generate_nonsense
      UUID.new.generate
    end

    def decrypt_token(raw_token)
      token = token_manager.decrypt raw_token
      token.symbolize_keys!
      token[:dn] = ActiveLdap::DistinguishedName.parse token[:dn]
      return token
  end


  end

 def self.included(base)
    base.extend(ClassMethods)
  end
end

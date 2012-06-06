
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

    def expired?(created)
      age = Time.now - created.to_time
      return age > self::LIFETIME
    end

    def find_and_validate(token)
      validate token
      self.find token[:dn]
    end

    def validate(token)
      if expired? token[:created]
        token_entry = self.find token[:dn]
        # Change the password so this token cannot be used again
        token_entry.userPassword = generate_nonsense
        token_entry.save!
        raise self::Expired.new "#{ self.to_s } expired", token
      end
      return true
    end

  end
 def self.included(base)
    base.extend(ClassMethods)
  end
end

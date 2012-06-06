
# Generic mixin for AccessToken and RefreshToken
module OAuthHelpers

  # Create new encrypted token
  def encrypt_token(extra)

    # Set token id only once
    self.puavoOAuthTokenId ||= UUID.new.generate

    # Change password so the encrypted token is different each time
    access_token_password = self.class.generate_nonsense
    self.userPassword = access_token_password

    save!

    access_token = self.class.token_manager.encrypt({
      "dn" => dn.to_s,
      "password" => access_token_password,
      "created" => Time.now,
    }.merge!(extra))

  end


  module ClassMethods

    def token_manager
      tm = Puavo::OAuth::TokenManager.new Puavo::OAUTH_CONFIG["token_key"]
    end

    def generate_nonsense
      UUID.new.generate
    end

    # Decrypt raw token to Ruby Hash
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

    # Find token entry and validate it
    def find_and_validate(token)
      validate token
      self.find token[:dn]
    end

    # Validate given token
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

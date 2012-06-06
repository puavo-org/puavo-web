
module OAuthHelpers


  module ClassMethods

    def token_manager
      tm = Puavo::OAuth::TokenManager.new Puavo::OAUTH_CONFIG["token_key"]
    end

    def generate_nonsense
      UUID.new.generate
    end


  end

 def self.included(base)
    base.extend(ClassMethods)
  end
end

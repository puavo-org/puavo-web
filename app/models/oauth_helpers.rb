
module OAuthHelpers

  def generate_nonsense
    UUID.new.generate
  end

  module ClassMethods

    def token_manager
      tm = Puavo::OAuth::TokenManager.new Puavo::OAUTH_CONFIG["token_key"]
    end


  end

 def self.included(base)
    base.extend(ClassMethods)
  end
end

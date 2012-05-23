module Puavo
  module Security
    def encrypt_userPassword
      if !self.userPassword.empty? && !self.userPassword.match(/^\{SSHA\}/)
        characters = (("a".."z").to_a + ("0".."9").to_a)
        salt = Array.new(16) { characters[rand(characters.size)] }.join
        self.userPassword = "{SSHA}" +
          Base64.encode64( Digest::SHA1.digest( self.userPassword +
                                                salt) +
                           salt).chomp!
      end
    end
  end
end

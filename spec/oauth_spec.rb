
require "json"
require "base64"
require "openssl"
require "digest/sha1"

require "lib/puavo/oauth"

describe Puavo::OAuth::TokenManager, "OAuth token manager" do

  token_manager = Puavo::OAuth::TokenManager.new "testkeysadfjasdkfaskdfasjsd"

  it "can create and decrypt token" do
    input_data = {
      "dn" => "puavoOAuthTokenId=12345678,ou=Tokens,ou=OAuth,dc=edu,dc=kunta1,dc=fi",
      "pw" => "password",
      "host" => "ldap1.example.com",
      "base" => "dc=edu,dc=kunta1,dc=fi",
    }

    token = token_manager.encrypt(input_data)

    token.class.should eq String # Base64

    output_data = token_manager.decrypt token

    input_data.keys.each do |key|
      output_data[key].should == input_data[key]
    end
  end

end

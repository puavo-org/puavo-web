
require "json"
require "base64"
require "openssl"
require "digest/sha1"
require "active_ldap"

require "lib/puavo/oauth"

describe Puavo::OAuth::TokenManager, "OAuth token manager" do

  token_manager = Puavo::OAuth::TokenManager.new "testkeysadfjasdkfaskdfasjsd"

  it "can create and decrypt token" do
    dn = "puavoOAuthAccessToken=12345678,ou=Tokens,ou=OAuth,dc=edu,dc=kunta1,dc=fi"
    pw = "password"

    token = token_manager.encrypt dn, pw

    token.class.should eq String # Base64

    d_dn, d_pw = token_manager.decrypt token

    d_dn.should eq dn
    d_pw.should eq pw
  end

end

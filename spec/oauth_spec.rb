
require "json"
require "base64"
require "openssl"
require "digest/sha1"
require "active_ldap"

require "lib/puavo/oauth"

describe Puavo::OAuth::TokenManager, "OAuth token manager" do

  token_manager = Puavo::OAuth::TokenManager.new "testkeysadfjasdkfaskdfasjsd"

  it "can create and decrypt token" do
    dn = "puavoOAuthTokenId=12345678,ou=Tokens,ou=OAuth,dc=edu,dc=kunta1,dc=fi"
    pw = "password"
    host = "ldap1.example.com"
    base = "dc=edu,dc=kunta1,dc=fi"

    token = token_manager.encrypt dn, pw, host, base

    token.class.should eq String # Base64

    d_dn, d_pw, d_host, d_base = token_manager.decrypt token

    d_dn.should eq dn
    d_pw.should eq pw
    d_host.should eq host
    d_base.should eq base
  end

end

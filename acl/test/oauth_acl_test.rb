
require "ruby-debug"

env = LDAPTestEnv.new
# http://www.openldap.org/faq/data/cache/1140.html

env.validate "create oc" do
  puts oauth_token

  owner.cannot_read oauth_client, [:displayName], InsufficientAccessRights
  student.cannot_modify oauth_client,   [:replace,  :displayName,  ["bad"]],              InsufficientAccessRights
  teacher.cannot_modify oauth_client,   [:replace,  :displayName,  ["bad"]],              InsufficientAccessRights


  student.can_add("#{ AccessToken.dn_attribute }=2,#{ AccessToken.base }", {
      :objectclass => ["simpleSecurityObject", "puavoOAuthAccessToken"],
      :puavoOAuthClient => oauth_client.dn.to_s,
      :puavoOAuthEduPerson => student.dn.to_s,
      :userPassword => "secret",
      :puavoOAuthTokenId => ["2"],
      :puavoOAuthScope => ["scope", "attributes", "here"],
      :puavoOAuthTokenType => ["bar"]
      # :type => "authorization_code",
  })

  oauth_client.cannot_add("#{ AccessToken.dn_attribute }=2,#{ AccessToken.base }", {
      :objectclass => ["simpleSecurityObject", "puavoOAuthAccessToken"],
      :puavoOAuthClient => oauth_client.dn.to_s,
      :puavoOAuthEduPerson => student.dn.to_s,
      :userPassword => "secret",
      :puavoOAuthTokenId => ["2"],
      :puavoOAuthScope => ["scope", "attributes", "here"],
      :puavoOAuthTokenType => ["bar"]
      # :type => "authorization_code",
  }, InsufficientAccessRights)


  student.cannot_modify oauth_token, [:replace, :userPassword, ["bad"]], InsufficientAccessRights
  student2.cannot_modify oauth_token, [:replace, :userPassword, ["bad"]], InsufficientAccessRights

  owner.can_modify oauth_token, [:replace, :puavoOAuthTokenType, ["foo"]]

  # student.cannot_modify oauth_token, [:replace, :type, ["access_token"]]
  # oauth_client.can_modify oauth_token, [:replace, :type, ["access_token"]]

end

# env.validate "oauth token deletion" do
#   student.can_delete oauth_token.dn
#   reset
#   student2.cannot_delete oauth_token.dn, InsufficientAccessRights
#   # oauth_client.cannot_delete oauth_token.dn, InsufficientAccessRights
# end



# env.validate "OAuth Access Token creation", false do
#
#   student.can_add :authorization_code, client_server.id
#   client_server.can_add :access_token, client_server.id
#
# end
#
# env.validate "OAuth Access Token cannot be added without Authorization Code", false do
#   client_server.cannot_add :authorization_code, client_server.id
# end
#
#
# env.validate "OAuth Access Token", false do
#
#   student_access_token.can_read student,        [:sn,       :givenName,  :uid]
#   student_access_token.can_read student2,       [:sn,       :givenName,  :uid]
#   student_access_token.can_read teacher,        [:sn,       :givenName,  :uid]
#   student_access_token.can_read admin,          [:sn,       :givenName,  :uid]
#
#   student_access_token.cannot_modify student,   [:replace,  :givenName,  ["bad"]],              InsufficientAccessRights
#   student_access_token.cannot_modify student2,  [:replace,  :givenName,  ["newname"]],          InsufficientAccessRights
#   student_access_token.cannot_modify student2,  [:replace,  :mail,       ["bad@example.com"]],  InsufficientAccessRights
#
#   teacher_access_token.cannot_modify student,   [:replace,  :givenName,  ["newname"]],          InsufficientAccessRights
#
#   admin_access_token.can_modify student,        [:replace,  :givenName,  ["newname"]]
#   admin_access_token.can_modify teacher,        [:replace,  :givenName,  ["newname"]]
#
#   teacher_access_token.cannot_modify admin,     [:replace,  :givenName,  ["newname"]],          InsufficientAccessRights
#
# end
#
#

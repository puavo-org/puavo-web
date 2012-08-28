
env = LDAPTestEnv.new

env.validate "create oc" do
  oauth_client
end

env.validate "OAuth Access Token creation", false do

  student.can_add :authorization_code, client_server.id
  client_server.can_add :access_token, client_server.id

end

env.validate "OAuth Access Token cannot be added without Authorization Code", false do
  client_server.cannot_add :authorization_code, client_server.id
end


env.validate "OAuth Access Token", false do

  student_access_token.can_read student,        [:sn,       :givenName,  :uid]
  student_access_token.can_read student2,       [:sn,       :givenName,  :uid]
  student_access_token.can_read teacher,        [:sn,       :givenName,  :uid]
  student_access_token.can_read admin,          [:sn,       :givenName,  :uid]

  student_access_token.cannot_modify student,   [:replace,  :givenName,  ["bad"]],              InsufficientAccessRights
  student_access_token.cannot_modify student2,  [:replace,  :givenName,  ["newname"]],          InsufficientAccessRights
  student_access_token.cannot_modify student2,  [:replace,  :mail,       ["bad@example.com"]],  InsufficientAccessRights

  teacher_access_token.cannot_modify student,   [:replace,  :givenName,  ["newname"]],          InsufficientAccessRights

  admin_access_token.can_modify student,        [:replace,  :givenName,  ["newname"]]
  admin_access_token.can_modify teacher,        [:replace,  :givenName,  ["newname"]]

  teacher_access_token.cannot_modify admin,     [:replace,  :givenName,  ["newname"]],          InsufficientAccessRights

end



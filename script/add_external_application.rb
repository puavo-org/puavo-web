# Usage: bundle exec rails runner script/add_external_application.rb

LdapBase.ldap_setup_connection(
  PUAVO_ETC.ldap_master,
  "o=Puavo",
  PUAVO_ETC.ldap_dn,
  PUAVO_ETC.ldap_password
)

app = ExternalApplication.new
app.classes = ["top", "puavoJWTService"]
app.cn = "Example application"
app.puavoServiceDomain = "app.example"
app.puavoServiceSecret = "secret"

app.save!
puts app.inspect


# Usage: bundle exec rails runner script/add_external_application.rb

def ask(question, default=nil)
  new_value = nil
  while true
    print "#{question} [#{ default }]> "
    new_value = STDIN.gets.strip

    # Use default or previous value if user did not give anything
    new_value = default if new_value.to_s.empty?

    # Break only when we have a value
    break if not new_value.to_s.empty?
  end
  new_value
end

LdapBase.ldap_setup_connection(
  ask("LDAP master", PUAVO_ETC.get(:ldap_master)),
  "o=Puavo",
  ask("LDAP admin dn", "uid=admin,o=puavo"),
  ask("LDAP admin pw", PUAVO_ETC.get(:ldap_password))
)

app = ExternalApplication.new
app.classes = ["top", "puavoJWTService"]

app.cn = ask "Name"
app.puavoServiceDomain = ask "Domain"
app.puavoServiceSecret = ask "Shared secret"
app.description = ask "Description"
app.mail = ask "Maintainer email"
app.puavoServiceDescriptionURL = ask "Description url"

puts app

if ask("Ok?", "y") == "y"
  app.save!
  puts app.inspect
else
  puts "abort"
end

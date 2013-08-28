# Usage: bundle exec rails runner script/add_external_application.rb

def ask(question, opts={})
  new_value = nil
  while true
    print "#{question} [#{ opts[:default] }]"
    print "(optional)" if opts[:optional]
    print "> "
    new_value = STDIN.gets.strip

    # Use default or previous value if user did not give anything
    new_value =  opts[:default] if new_value.to_s.empty?

    # Break if we have value
    break if not new_value.to_s.empty?

    # Allow empty value in optional
    break if opts[:optional]
  end
  new_value
end

LdapBase.ldap_setup_connection(
  ask("LDAP master", :default => PUAVO_ETC.get(:ldap_master)),
  "o=Puavo",
  ask("LDAP admin dn", :default => "uid=admin,o=puavo"),
  ask("LDAP admin pw", :default => PUAVO_ETC.get(:ldap_password))
)

app = ExternalApplication.new
app.classes = ["top", "puavoJWTService"]

app.cn = ask "Name"
app.puavoServiceDomain = ask "Domain"
app.puavoServicePathPrefix = ask "Path prefix", :optional => true
app.puavoServiceSecret = ask "Shared secret"
app.description = ask "Description"
app.mail = ask "Maintainer email"
app.puavoServiceDescriptionURL = ask "Description url", :optional => true

puts
if ask("Ok?", :default => "y") == "y"
  app.save!
  puts "saved"
else
  puts "abort"
end

# Usage: bundle exec rails runner script/add-external-service.rb

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

ExternalService.ldap_setup_connection(
  ask("LDAP master", :default => PUAVO_ETC.get(:ldap_master)),
  "o=Puavo",
  ask("LDAP admin dn", :default => "uid=admin,o=puavo"),
  ask("LDAP admin pw", :default => PUAVO_ETC.get(:ldap_password))
)

puts "Current services:"
ExternalService.all.each do |ea|
  puts "#{ ea.cn } - #{ ea.puavoServiceDomain } #{ ea.puavoServicePathPrefix }"
end
puts

app = ExternalService.new
app.classes = ["top", "puavoJWTService"]

app.cn = ask "Name"
app.puavoServiceDomain = ask "Domain"
app.puavoServicePathPrefix = ask "Path prefix", :optional => true
app.puavoServiceSecret = ask "Shared secret"
app.description = ask "Description"
app.mail = ask "Maintainer email"
app.puavoServiceDescriptionURL = ask "Description url", :optional => true
app.puavoServiceTrusted = ask("Trusted y/n?", :default => "n") == "y"

puts
if ask("Ok?", :default => "y") == "y"
  app.save!
  puts "saved"
else
  puts "abort"
end

# Usage
#
# Add new ExternalService:
#
#   bundle exec rails runner script/add-external-service.rb
#
# Update existing shared secret:
#
#   bundle exec rails runner script/add-external-service.rb <domain> [path prefix]
#

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



if ARGV.size > 0
  apps = ExternalService.all.select do |app|

    domain_ok = app.puavoServiceDomain == ARGV[0]

    if ARGV[1]
      path_ok = app.puavoServicePathPrefix == ARGV[1]
    else
      path_ok = true
    end

    domain_ok && path_ok
  end

  if apps.empty?
    puts "Cannot find ExternalService with #{ ARGV.inspect }"
    exit 1
  end

  if apps.size != 1
    puts "Invalid ExternalService selection with #{ ARGV.inspect }"
    exit 1
  end

  app = apps.first
  puts
  puts app.cn
  puts
  app.puavoServiceSecret = ask "Shared secret", :default => app.puavoServiceSecret
  app.save!
  puts "saved"
  exit 0
end


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

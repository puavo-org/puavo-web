# RAILS_ENV=production bundle exec rails r script/args.rb

require 'optparse'

BANNER = "Puavo External Services Manager v0.1\n"
DEFAULT_LDAP_MASTER = PUAVO_ETC.get(:ldap_master)
DEFAULT_LDAP_USER = 'uid=admin,o=puavo'

# --------------------------------------------------------------------------------------------------
# Utility

def help
  puts BANNER
  puts <<EOD

Usage: manage.rb <command> [parameters] [--ldap-master <address>] [--ldap-user <user>]

Commands:
    list
      List all external services and their details. THIS CONTAINS PLAIN-TEXT
      SHARED SECRETS, do not run if someone's looking at the terminal behind
      your back.

    activate
      Activate a service in the specified organisation or school.
      Accepts --organisation, and optionally --school with one or more
      school abbreviations. If --school is omitted, deactivates an
      organisation-level service.

    deactivate
      Deactivate the service in the specified organisation or school.
      Accepts the sam arguments as "activate".

    set-domain
      Change the activated domain(s) of an existing service. Wants --service
      argument that identifies the target service. Unless --domain is used,
      will prompt for a comma-separated list of one or more domains.

    set-secret
      Change the shared secret of an existing service. Wants --service
      argument that identifies the target service. Will prompt for the
      new secret.

Arguments:

    --organisation domain       Domain of the target organisation (not name)
    --school a[,b[,c...]        One or more school abbreviations
    --service DN                Name of the target service
    --domain a[,b[,c...N]       Comma-separated list of service domains (see set-domain);
                                the list cannot contain any whitespace.

You can use --ldap-master and -ldap-user to change the default LDAP server
settings. The LDAP password is *always* prompted for, it cannot be specified
on the command line. The default LDAP master address is "#{DEFAULT_LDAP_MASTER}"
and the user is "#{DEFAULT_LDAP_USER}".

EOD

end

def error_exit(msg)
  puts "ERROR: #{msg}"
  exit(1)
end

def with_padding(title, value, quote: false, width: 20, indent: 4)
  str = ''
  str << ' ' * indent if indent > 0
  str << title.ljust(width, '.')
  str << ': '

  if value.nil?
    str << '(nil)'
  else
    str << '"' if quote
    str << value
    str << '"' if quote
  end

  puts str
end

def read_string(prompt)
  s = nil

  loop do
    begin
      print prompt
      s = $stdin.gets.strip
    rescue Interrupt
      return nil
    end

    return s if !s.nil? && !s.empty?
  end
end

def read_password(prompt)
  print "#{prompt}: "
  system('stty', '-echo');
  password = STDIN.gets.chomp
  system('stty', 'echo')
  puts ''

  password
end

# --------------------------------------------------------------------------------------------------
# Data manipulation stuff

def connect_to_ldap(organisation, args)
  puts 'Connecting to the database...'

  password = read_password('Enter the LDAP password (will not echo, Ctrl+C to cancel)')

  credentials = {
    organisation_key: organisation.include?('.') ? organisation.split('.')[0] : organisation,
    dn: ActiveLdap::DistinguishedName.parse(args.fetch(:ldap_user, DEFAULT_LDAP_USER)),
    password: password,
  }

  authentication = Puavo::Authentication.new
  authentication.configure_ldap_connection(credentials)
  authentication.authenticate
end

# Determines if the DN points to a valid external service
def validate_service_dn(dn)
  if ExternalService.all.find { |e| e.dn == dn }.nil?
    error_exit("DN \"#{dn}\" does not identify a known external service, nothing done")
  end
end

# Determines if the school list contains an invalid abbreviation
def _validate_abbreviations(schools, abbreviations)
  valid = schools.collect { |s| s.cn }.to_set
  missing = abbreviations - valid

  unless missing.empty?
    error_exit("\"#{missing.first}\" is not a valid school abbreviation, nothing done")
  end
end

# Adds the service DN to the list of active services
def _add_service(object, service)
  if object.puavoActiveService.nil?
    object.puavoActiveService = service
  else
    object.puavoActiveService = Array(object.puavoActiveService).collect { |dn| dn.to_s } + [service]
  end
end

# Removes the service DN from the list of active services
def _remove_service(object, service)
  services = Array(object.puavoActiveService).collect { |dn| dn.to_s }
  object.puavoActiveService = services.reject { |dn| dn.to_s.downcase == service.downcase }
end

# --------------------------------------------------------------------------------------------------
# Action handlers

def list_services(args)
  puts 'Connecting to the database...'

  password = read_password('Enter the LDAP master password (will not echo, Ctrl+C to cancel)')

  ExternalService.ldap_setup_connection(
    args.fetch(:ldap_master, DEFAULT_LDAP_MASTER),
    'o=Puavo',
    args.fetch(:ldap_user, DEFAULT_LDAP_USER),
    password,
  )

  all = ExternalService.all

  if all.empty?
    puts 'No external services, nothing to list'
    return
  end

  puts "Have #{all.count} external service(s):"

  all.each_with_index do |e, index|
    puts "Service #{index + 1}:"

    extra = ExternalService.find(e.dn, attributes: ['createTimestamp'])
    created = extra['createTimestamp'] ? Time.at(extra['createTimestamp']).localtime.strftime('%Y-%m-%d %H:%M:%S') : nil

    with_padding('Domain(s)', Array(e.puavoServiceDomain).join(','))
    with_padding('Trusted (verified SSO)?', e.puavoServiceTrusted ? 'Yes' : 'No')
    with_padding('Description', e.description, quote: true)
    with_padding('Description URL', e.puavoServiceDescriptionURL, quote: true)
    with_padding('Prefix', e.puavoServicePathPrefix, quote: true)
    with_padding('Maintainer email', e.mail, quote: true)
    with_padding('Shared secret', e.puavoServiceSecret, quote: true)
    with_padding('DN', e.dn.to_s)
    with_padding('Created', created ? created : '?')
  end

  puts 'Done'
end

def set_service_property(args, property)
  unless args.include?(:service)
    error_exit('Use --service to specify which external service (identified by its DN) you want to edit')
  end

  password = read_password('Enter the LDAP master password (will not echo, Ctrl+C to cancel)')

  ExternalService.ldap_setup_connection(
    args.fetch(:ldap_master, DEFAULT_LDAP_MASTER),
    'o=Puavo',
    args.fetch(:ldap_user, DEFAULT_LDAP_USER),
    password,
  )

  service = ExternalService.all.find { |e| e.dn.to_s.downcase == args[:service].downcase }

  if service.nil?
    error_exit("DN \"#{args[:service]}\" does not identify a known external service, nothing done")
  end

  if property == :domain && args.include?(:domain)
    # Set the domains directly
    puts "Setting the domain list of the service \"#{service.cn}\" to #{args[:domain]}"

    service.puavoServiceDomain = args[:domain].split(',')

    begin
      service.save!
    rescue StandardError => e
      error_exit("Could not save the service: #{e}")
    end

    return
  end

  puts "Editing service \"#{service.cn}\". Press Ctrl+C to cancel."

  case property
    when :secret
      loop do
        new_secret = read_string("Enter a new shared secret (at least 25 characters long): ")

        if new_secret.nil?
          puts "\n[Canceled]\n"
          return
        end

        if new_secret.length < 25
          puts 'The shared secret must be at least 25 characters long, try again'
        else
          service.puavoServiceSecret = new_secret
          break
        end
      end

    when :domain
      puts "The current domains for this service are: #{service.puavoServiceDomain.join(',')}"

      loop do
        new_domain = read_string("Enter a list of one or more domains, separated by comma: ")

        if new_domain.nil?
          puts "\n[Canceled]\n"
          return
        end

        if new_domain.include?(' ') || new_domain.include?("\t")
          puts 'No whitespace allowed, try again'
        else
          service.puavoServiceDomain = new_domain.split(',')
          break
        end
      end

    else
      error_exit("Unknown property \"#{property}\"")
  end

  begin
    service.save!
  rescue StandardError => e
    error_exit("Could not save the service: #{e}")
  end

  puts 'Done'
end

def activate_service(args)
  unless args.include?(:organisation)
    error_exit('Use --organisation to specify the target organisation')
  end

  unless args.include?(:service)
    error_exit('Use --service to specify which external service (identified by its DN) you want to activate')
  end

  organisation = args[:organisation]

  if organisation.count > 1
    error_exit('You can specify only one organisation at a time')
  end

  organisation = organisation.first
  connect_to_ldap(organisation, args)

  validate_service_dn(args[:service])

  if args.include?(:school)
    all_schools = School.all
    _validate_abbreviations(all_schools, args[:school])

    all_schools.each do |school|
      next unless args[:school].include?(school.cn)

      active = Array(school.puavoActiveService || []).collect { |dn| dn.to_s.downcase }.to_set

      if active.include?(args[:service].downcase)
        puts "The specified external service is already active in school #{school.displayName} (#{school.cn}), skipped"
        next
      end

      puts "Activating external service in school #{school.displayName} (#{school.cn})"
      _add_service(school, args[:service])

      begin
        school.save!
      rescue StandardError => e
        error_exit("Could not save the school: #{e}")
      end
    end
  else
    # Organisation-level activation
    o = LdapOrganisation.current
    active = Array(o.puavoActiveService || []).collect { |dn| dn.to_s.downcase }.to_set

    if active.include?(args[:service].downcase)
      puts 'The specified external service is already active in the target organisation, nothing done'
      exit(0)
    end

    puts "Activating organisation-level external service #{args[:service]} in organisation #{organisation}"
    _add_service(o, args[:service])

    begin
      o.save!
    rescue StandardError => e
      error_exit("Could not save the organisation: #{e}")
    end
  end

  puts 'Done'
end

def deactivate_service(args)
  unless args.include?(:organisation)
    error_exit('Use --organisation to specify the target organisation')
  end

  unless args.include?(:service)
    error_exit('Use --service to specify which external service (identified by its DN) you want to deactivate')
  end

  organisation = args[:organisation]

  if organisation.count > 1
    error_exit('You can specify only one organisation at a time')
  end

  organisation = organisation.first
  connect_to_ldap(organisation, args)

  validate_service_dn(args[:service])

  if args.include?(:school)
    # School-level activation(s)
    all_schools = School.all
    _validate_abbreviations(all_schools, args[:school])

    all_schools.each do |school|
      next unless args[:school].include?(school.cn)

      active = Array(school.puavoActiveService || []).collect { |dn| dn.to_s.downcase }.to_set

      unless active.include?(args[:service].downcase)
        puts "The specified external service is not active in school #{school.displayName} (#{school.cn}), skipped"
        next
      end

      puts "Deactivating external service in school #{school.displayName} (#{school.cn})"
      _remove_service(school, args[:service])

      begin
        school.save!
      rescue StandardError => e
        error_exit("Could not save the school: #{e}")
      end
    end
  else
    # Organisation-level deactivation
    o = LdapOrganisation.current
    active = Array(o.puavoActiveService || []).collect { |dn| dn.to_s.downcase }.to_set

    unless active.include?(args[:service].downcase)
      puts 'The specified external service is not active in the target organisation, nothing done'
      exit(0)
    end

    puts "Deactivating organisation-level external service #{args[:service]} in organisation #{organisation}"
    _remove_service(o, args[:service])

    begin
      o.save!
    rescue StandardError => e
      error_exit("Could not save the organisation: #{e}")
    end
  end

  puts 'Done'
end

# --------------------------------------------------------------------------------------------------
# Main

parser = OptionParser.new(BANNER)
args = {}

parser.on('', '--ldap-master address',  '') do |address|
  args[:ldap_master] = address
end

parser.on('', '--ldap-user user', '') do |user|
  args[:ldap_user] = user
end

parser.on('', '--organisation organisation', '') do |organisation|
  args[:organisation] = organisation.split(',').to_set
end

parser.on('', '--school school', '') do |school|
  args[:school] = school.split(',').to_set
end

parser.on('', '--service dn', '') do |dn|
  args[:service] = dn
end

parser.on('', '--domain domain', '') do |domain|
  if domain.include?(' ') || domain.include?("\t")
    error_exit('The domain list cannot contain whitespace')
  end

  args[:domain] = domain
end

if ARGV.length < 1
  help
  exit(1)
end

action = ARGV[0]
ARGV.shift

begin
  parser.parse! unless ARGV.empty?
rescue StandardError => e
  error_exit(e)
end

case action
  when 'list'
    list_services(args)

  when 'activate'
    activate_service(args)

  when 'deactivate'
    deactivate_service(args)

  when 'set-domain'
    set_service_property(args, :domain)

  when 'set-secret'
    set_service_property(args, :secret)

  else
    error_exit("Unknown action \"#{action}\"")
end

exit(0)

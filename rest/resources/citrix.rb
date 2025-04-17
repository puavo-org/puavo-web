# Atria Cortex API glue for Citrix integration
# Some documentation: https://support.automate101.com/portal/en/kb/articles/atria-api-user-guide

# NOTE: The XML templates used in the API queries are not part of the puavo-users repo at the moment.

require 'nokogiri'
require_relative '../lib/integrations'

module PuavoRest

# Taken directly from the documentation
CORTEX_ERROR_CODES = {
  0 => 'Unknown',
  1 => 'CustomerError',
  2 => 'TemplateNotFound',
  3 => 'InvalidXmlFormat',
  4 => 'InvalidObject',
  5 => 'InvalidAction',
  6 => 'InvalidNewCustomer',
  7 => 'InvalidUnlimited',
  8 => 'InvalidNumericDelta',
  9 => 'InvalidNumericType',
  10 => 'InvalidService',
  11 => 'NotAuthenticated',
  12 => 'NotAuthorized',
  13 => 'ReportError',
  14 => 'ReportNotFound',
  15 => 'InvalidUser',
  16 => 'UserNotFound',
  17 => 'InvalidStatus',
  18 => 'InvalidReference',
  19 => 'InvalidProperty',
  20 => 'LocationNotFound',
  21 => 'ServiceNotFound',
  22 => 'RoleNotFound',
  23 => 'CitrixItemNotFound',
  24 => 'CitrixItemInUse',
  25 => 'CitrixCollectionNotFound',
  26 => 'CitrixCollectionInvalid',
  27 => 'LocationError',
  28 => 'TokenNotFound',
  29 => 'BrandTypeNotFound',
  30 => 'BrandNameNotFound',
  31 => 'HMCNotValid',
  32 => 'InvalidBoolean',
  33 => 'InvalidKey',
  34 => 'CustomerNotFound',
  35 => 'PasswordNeverExpiredNotAllowed',
  36 => 'InvalidAccountExpiration',
  37 => 'InvalidPasswordExpiration',
  38 => 'InvalidInteger',
}.freeze

class AtriaCortexAPIError < StandardError
  attr_reader :code, :message

  def initialize(code, message)
    @code = code
    @message = message

    cortex_message = CORTEX_ERROR_CODES.fetch(code, nil)

    if cortex_message.nil?
      super("Unhandled unknown Atria Cortex API error #{@code}")
    else
      super("Unhandled Atria Cortex API error #{@code} (#{@message})")
    end
  end
end

class AtriaCortexAPI
  def initialize(config)
    @config = config
  end

  # Fills in the named parameter placeholders in an XML template
  def prepare_query(filename, parameters={})
    query = File.read(filename)

    # Replace parameters
    parameters.each do |key, value|
      query.gsub!("[#{key}]", value)
    end

    # Remove unreplaced parameters (they can cause errors)
    query.gsub(/\[.+\]/, '')
  end

  # Executes a prepared XML query. Does not handle errors.
  def do_query(query)
    uri = URI.parse(@config['endpoint'])

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.instance_of?(URI::HTTPS)
    http.open_timeout = 5
    http.read_timeout = 10

    post = Net::HTTP::Post.new(uri.request_uri)
    post['Content-Type'] = 'application/xml'
    post.basic_auth(@config['username'], @config['password'])
    post.body = query

    http.request(post)
  end

  def make_upn(username)
    "#{username}@#{@config['domain']}"
  end

  def get_user(username)
    query = prepare_query('lib/citrix/find_single_user.xml', {
      'customer' => @config['customer'],
      'user' => username
    })

    result = do_query(query)
    body_s = result.body.to_s
    body = Nokogiri.XML(body_s)

    unless body.xpath('//error').empty?
      code = body.xpath('//error/id').children[0].to_s.to_i
      return false if code == 16    # "UserNotFound"

      message = body.xpath('//error/message').children[0].to_s
      raise AtriaCortexAPIError.new(code, message)
    end

    body
  end

  def create_user(first_name, last_name, username, password)
    query = prepare_query('lib/citrix/create_user.xml', {
      'customer' => @config['customer'],
      'name' => "#{username}_#{@config['customer']}",
      'upn' => make_upn(username),
      'fullname' => "#{first_name} #{last_name}",
      'first_name' => first_name,
      'last_name' => last_name,
      'password' => password,
      'password_force_change' => 'False',
    })

    result = do_query(query)
    body_s = result.body.to_s
    body = Nokogiri.XML(body_s)

    unless body.xpath('//error').empty?
      code = body.xpath('//error/id').children[0].to_s.to_i
      message = body.xpath('//error/message').children[0].to_s
      raise AtriaCortexAPIError.new(code, message)
    end

    body
  end

  def list_applications(username, rlog)
    query = prepare_query('lib/citrix/list_user_applications.xml', {
      'customer' => @config['customer'],
      'user' => username
    })

    result = do_query(query)
    body_s = result.body.to_s
    body = Nokogiri.XML(body_s)

    unless body.xpath('//error').empty?
      code = body.xpath('//error/id').children[0].to_s.to_i
      message = body.xpath('//error/message').children[0].to_s
      raise AtriaCortexAPIError.new(code, message)
    end

    config_services = @config['provisioning']['services']
    applications = {}

    # Each available service...
    body.xpath('//user/service').each do |service_node|
      service_name = service_node.xpath('name').text
      next unless config_services.include?(service_name)

      config_collections = config_services[service_name].fetch('collections', {})

      # Each available service server collection...
      service_node.xpath('servercollection').each do |collection_node|
        collection_name = collection_node.xpath('name').text
        next unless config_collections.include?(collection_name)

        config_applications = config_collections[collection_name]

        # Each available application in a server collection...
        collection_node.xpath('applications/application').each do |application_node|
          name = application_node.xpath('name').text
          next unless config_applications.include?(name)

          adname = application_node.xpath('adname').text
          enabled = application_node.xpath('enabled').text == 'True'

          applications[name] = {
            desired: config_applications[name]['enabled'],
            actual: enabled,
            adname: adname,
          }
        end
      end
    end

    applications
  end

  # Provisions a single application
  def provision_application(username, application_name, adname, state, rlog)
    query = prepare_query('lib/citrix/provision_application.xml', {
      '0' => @config['customer'],
      '1' => username,
      '2' => application_name,
      '3' => (state == true) ? 'True' : 'False',
      '4' => adname,
    })

    result = do_query(query)
    body_s = result.body.to_s
    body = Nokogiri.XML(body_s)

    unless body.xpath('//error').empty?
      code = body.xpath('//error/id').children[0].to_s.to_i
      message = body.xpath('//error/message').children[0].to_s
      raise AtriaCortexAPIError.new(code, message)
    end
  end

  # Provisions multiple applications in one call
  def provision_multiple_applications(username, application_states, rlog)
    # Duplicate the single application template for every application
    # and combine them into one. I tried to do this by loading the XML
    # template using Nokogiri, then by duplicating the nodes in the tree,
    # but that turned out to be so difficult I decided to just concatenate
    # strings.
    application_template = File.read('lib/citrix/application_template.xml')

    states_xml = ''

    application_states.each do |name, state|
      next if state['desired'] == state['actual']

      xml = application_template.dup
      xml.gsub!('[0]', name)
      xml.gsub!('[1]', state['adname'])
      xml.gsub!('[2]', (state['desired'] == true) ? 'True' : 'False')
      states_xml += xml
    end

    # Build the full query and run it normally
    query = prepare_query('lib/citrix/provision_multiple_applications.xml', {
      '0' => @config['customer'],
      '1' => username,
      '2' => states_xml
    })

    result = do_query(query)
    body_s = result.body.to_s
    body = Nokogiri.XML(body_s)

    unless body.xpath('//error').empty?
      code = body.xpath('//error/id').children[0].to_s.to_i
      message = body.xpath('//error/message').children[0].to_s
      raise AtriaCortexAPIError.new(code, message)
    end
  end

  def list_application_provisioning_progress(username, rlog)
    query = prepare_query('lib/citrix/list_application_provisioning_progress.xml', {
      '0' => @config['customer'],
      '1' => username,
      '2' => 'Citrix',
    })

    result = do_query(query)
    body_s = result.body.to_s
    body = Nokogiri.XML(body_s)

    unless body.xpath('//error').empty?
      code = body.xpath('//error/id').children[0].to_s.to_i
      message = body.xpath('//error/message').children[0].to_s
      raise AtriaCortexAPIError.new(code, message)
    end

    body.xpath('//user/service/status').children[0].to_s
  end
end

class Citrix < PuavoSinatra
  def citrix_return(status, error: nil, data: nil)
    halt 200, json({
      request_id: @request_id,
      status: status,
      error: error,
      data: data
    })
  end

  def handle_citrix_phase(phase)
    auth :basic_auth, :kerberos

    @request_id = Puavo::Integrations.generate_synchronous_call_id

    unless CONFIG.include?('citrix')
      # tested
      rlog.error("[#{@request_id}] Citrix licensing configuration not found, doing nothing")
      citrix_return('error', error: { puavo: { message: 'no_citrix_configuration' } })
    end

    user = User.current
    organisation = LdapModel.organisation

    rlog.info("[#{@request_id}] Citrix licensing and provisioning phase \"#{phase}\" for user \"#{user.username}\" in organisation \"#{organisation.domain}\"")

    # Load per-organisation Citrix configuration
    unless CONFIG['citrix'].include?(organisation.domain)
      # tested
      rlog.error("[#{@request_id}] Citrix licensing is not enabled in this organisation")
      citrix_return('error', error: { puavo: { message: 'citrix_not_active_in_this_organisation' } })
    end

    config = CONFIG['citrix'][organisation.domain]
    atria = AtriaCortexAPI.new(config)

    # Read the current license data from Puavo
    license = get_puavo_citrix_license_data(user)
    license['domain'] = config['puavo_domain']
    rlog.info("[#{@request_id}] The generated Citrix username is \"#{license['username']}\"")

    case phase
      # --------------------------------------------------------------------------------------------
      when :check_user
        rlog.info("[#{@request_id}] Retrieving the user status from Citrix...")
        atria_user = atria.get_user(license['username'])

        if atria_user
          # tested
          rlog.info("[#{@request_id}] The user already exists in Citrix")
          status = 'user_exists'
        else
          # tested
          rlog.info("[#{@request_id}] The user does not exist in Citrix")
          status = 'user_does_not_exist'
        end

        # Must be done here because the Cortex API does not accept usernames with the domain
        license['username'] += '@' + config['domain']
        citrix_return(status, data: { license: license })

      # --------------------------------------------------------------------------------------------
      when :create_new_user
        # tested
        rlog.info("[#{@request_id}] Creating a new user")
        data = atria.create_user(license['first_name'], license['last_name'], license['username'], license['password'])
        citrix_return('user_creation_in_progress')

      # --------------------------------------------------------------------------------------------
      when :check_new_user
        rlog.info("[#{@request_id}] Checking if the new user (#{license['username']}) has been created")
        atria_user = atria.get_user(license['username'])

        if atria_user == false
          # tested
          rlog.error("[#{@request_id}] New user creation not in progress")
          citrix_return('user_creation_not_in_progress')
        end

        begin
          status = atria_user.xpath('//user/status').children[0].to_s
        rescue StandardError => e
          # not tested
          rlog.error("[#{@request_id}] Cannot parse the returned XML: #{e}")
          rlog.error("[#{@request_id}] Raw XML data: #{atria_user.to_s}")
          citrix_return('xml_parsing_failed')
        end

        if status == 'Provisioned'
          # tested
          rlog.info("[#{@request_id}] New user has been created")
          citrix_return('user_created')
        elsif status == 'InProgress'
          # tested
          rlog.info("[#{@request_id}] New user creation is in progress")
          citrix_return('user_creation_in_progress')
        elsif status == 'Requested'
          # tested
          rlog.info("[#{@request_id}] New user creation requested")
          citrix_return('user_creation_requested')
        end

        # not tested (don't know how to get here)
        rlog.info("[#{@request_id}] Unknown status \"#{status}\"")
        citrix_return('unknown_user_provisioning_status')

      # --------------------------------------------------------------------------------------------
      when :get_app_provisioning
        # tested
        rlog.info("[#{@request_id}] Getting the application provisioning states")
        applications = atria.list_applications(license['username'], rlog)
        citrix_return('ok', data: { application_states: applications })

      # --------------------------------------------------------------------------------------------
      when :set_app_provisioning
        rlog.info("[#{@request_id}] Setting the application provisioning states")

        # Parse the incoming application state data
        body = request.body.read

        begin
          applications = JSON.parse(body)
        rescue StandardError => e
          # tested
          rlog.error("[#{@request_id}] Cannot parse the request body JSON: #{e}")
          rlog.error("[#{@request_id}] Raw body data: #{e}")
          citrix_return('json_parsing_error')
        end

        # Detect changes
        change_these = []

        applications['application_states'].each do |name, state|
          next if state['desired'] == state['actual']
          rlog.info("[#{@request_id}] Changing the enabled state of \"#{name}\" from \"#{state['actual']}\" to \"#{state['desired']}\"")
          change_these << name
        end

        if change_these.empty?
          # tested
          rlog.info("[#{@request_id}] No changes need to be done to provisioning states")
          citrix_return('nothing_to_do')
        end

        atria.provision_multiple_applications(license['username'], applications['application_states'], rlog)

        rlog.info("[#{@request_id}] Application provisioning changes complete")
        citrix_return('ok')

      # --------------------------------------------------------------------------------------------
      when :list_application_provisioning_progress
        rlog.info("[#{@request_id}] Getting the current application provisioning progress")

        begin
          user_service_status = atria.list_application_provisioning_progress(license['username'], rlog)
          rlog.info("[#{@request_id}] Received application provisioning status '#{ user_service_status }'")
          case user_service_status
            when 'Failed'
              citrix_return('application_provisioning_failed')
            when 'InProgress'
              citrix_return('application_provisioning_in_progress')
            when 'Provisioned'
              citrix_return('ok')
            when 'Requested'
              citrix_return('application_provisioning_requested')
            else
              raise "unknown service status: '#{ user_service_status }'"
          end
        rescue StandardError => e
          rlog.error("[#{@request_id}] Error in getting the current application provisioning progress: #{ e.message }")
          citrix_return('error')
        end

      # --------------------------------------------------------------------------------------------
      else
        # tested
        citrix_return('error', error: { puavo: { message: 'invalid_phase_id' } })
    end
  rescue AtriaCortexAPIError => e
    # tested
    rlog.error("[#{@request_id}] #{e}")

    citrix_return('error',
      error: {
        citrix: {
          code: e.code,
          message: e.message
        }
      }
    )
  end

  # Phase 1: Checks if the user account exists in Citrix
  get '/v3/users/:username/citrix/check_user' do
    return handle_citrix_phase(:check_user)
  end

  # Phase 2A: Initiates the asynchronous user creation in Citrix. You need to call phase 1 endpoint
  # in a loop until the user account is created.
  get '/v3/users/:username/citrix/create_new_user' do
    return handle_citrix_phase(:create_new_user)
  end

  # Phase 2B: Checks the status of the newly-created user
  get '/v3/users/:username/citrix/check_new_user' do
    return handle_citrix_phase(:check_new_user)
  end

  # Phase 3
  get '/v3/users/:username/citrix/get_app_provisioning' do
    return handle_citrix_phase(:get_app_provisioning)
  end

  # Phase 4 (optional, depends on phase 3)
  post '/v3/users/:username/citrix/set_app_provisioning' do
    return handle_citrix_phase(:set_app_provisioning)
  end

  # Phase 4B (optional, depends on phase 3)
  get '/v3/users/:username/citrix/list_application_provisioning_progress' do
    return handle_citrix_phase(:list_application_provisioning_progress)
  end

  # All-in-one (old, don't call anymore, will be deleted soon-ish)
  get '/v3/users/:username/citrix' do
    auth :basic_auth, :kerberos

    @request_id = Puavo::Integrations.generate_synchronous_call_id

    unless CONFIG.include?('citrix')
      rlog.error("[#{@request_id}] Citrix licensing configuration not found, doing nothing")

      return json({
        request_id: @request_id,
        status: 'error',
        error: {
          puavo: {
            message: 'no_citrix_configuration'
          },
        },
        data: nil
      })
    end

    user = User.current
    organisation = LdapModel.organisation

    rlog.info("[#{@request_id}] Handling Citrix licensing and provisioning for user \"#{user.username}\" in organisation \"#{organisation.domain}\"")

    unless CONFIG['citrix'].include?(organisation.domain)
      rlog.error("[#{@request_id}] Citrix licensing is not enabled in this organisation")

      return json({
        request_id: @request_id,
        status: 'error',
        error: {
          puavo: {
            message: 'citrix_not_active_in_this_organisation'
          },
        },
        data: nil
      })
    end

    config = CONFIG['citrix'][organisation.domain]

    license = get_puavo_citrix_license_data(user)
    license['domain'] = config['puavo_domain']
    rlog.info("[#{@request_id}] The generated Citrix username is \"#{license['username']}\"")

    atria = AtriaCortexAPI.new(config)

    # Create the user if they don't already exist
    atria_user = atria.get_user(license['username'])

    unless atria_user
      rlog.info("[#{@request_id}] The user does not exist in Citrix yet, creating")
      new_user = atria.create_user(license['first_name'], license['last_name'], license['username'], license['password'])

      rlog.info("[#{@request_id}] User created, waiting for the account to be provisioned")

      # The account has been created, now we must wait until it actually becomes usable.
      # Atria appears to call this "provisioning". This is not the same as provisioning
      # applications for the user.
      count = 1

      loop do
        if count > 10
          rlog.error("[#{@request_id}]     This is taking too long, aborting")

          return json({
            request_id: @request_id,
            status: 'error',
            error: {
              puavo: {
                message: 'cannot_provision_new_account'
              },
            },
            data: nil
          })
        end

        rlog.info("[#{@request_id}]     Attempt #{count}/5...")

        atria_user = atria.get_user(license['username'])

        # TODO: Should we also check the values of "enabled" and "approvalpending" nodes?
        status = atria_user.xpath('//user/status').children[0].to_s
        break if status == 'Provisioned'

        count += 1
        sleep(2)
      end

      rlog.info("[#{@request_id}]     New account provisioning complete")
    end

    # Set the provisioning states of the applications listed in the configuration
    rlog.info("[#{@request_id}] Retrieving a list of provisioned applications...")

    applications = atria.list_applications(license['username'], rlog)
    change_these = []

    applications.each do |name, state|
      next if state[:desired] == state[:actual]
      change_these << name
    end

    if change_these.empty?
      rlog.info("[#{@request_id}] No changes need to be done to provisioning states")
    else
      change_these.each do |name|
        application = applications[name]
        rlog.info("[#{@request_id}] Changing the enabled state of \"#{name}\" to \"#{application[:desired]}\"")
        atria.provision_application(license['username'], name, application[:adname], application[:desired], rlog)
      end

      rlog.info("[#{@request_id}] Application provisioning changes complete")
    end

    # Must be done here because the Cortex API does not accept usernames with the domain
    license['username'] += '@' + config['domain']

    json({
      request_id: @request_id,
      status: 'success',
      error: nil,
      data: {
        license: license
      }
    })
  rescue AtriaCortexAPIError => e
    rlog.error("[#{@request_id}] #{e}")

    json({
      request_id: @request_id,
      status: 'error',
      error: {
        citrix: {
          code: e.code,
          message: e.message
        }
      },
      data: nil
    })
  end

private
  # Ensures the password has at least one digit, one lowercase letter, and one uppercase letter
  def valid_password?(str)
    return false unless /\d/.match(str)
    return false unless /[a-z]/.match(str)
    return false unless /[A-Z]/.match(str)
    true
  end

  # Generates a random Citrix-compatible password
  def generate_password
    password_chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz01234567890'.split('')

    loop do
      password = password_chars.sample(15).join
      return password if valid_password?(password)
    end
  end

  # Returns the Citrix license data for this user. If it does not exist yet, builds it first.
  def get_puavo_citrix_license_data(user)
    citrix_id = JSON.parse(user.citrix_id || '{}')

    unless citrix_id.include?('first_name') && citrix_id.include?('last_name')
      rlog.info("[#{@request_id}] Generating new Citrix licensing data and storing it in Puavo")

      # Our clients do not want to use real names
      first_name, last_name = pseudonymize(user.uuid)

      # The username has serious length limitations (20 character max and the customer name is
      # included in it), so use 14 characters from the middle of the UUID.
      username = user.uuid[9..22].gsub!('-', '_')

      now = make_timestamp()

      citrix_id = {
        'created' => now,
        'last_used' => now,
        'first_name' => first_name,
        'last_name' => last_name,
        'username' => username,
        'password' => generate_password()
      }

      # Normal users don't have enough rights to call "user.save!", so update the attribute directly
      user.class.ldap_op(:modify, user.dn, [
        LDAP::Mod.new(LDAP::LDAP_MOD_REPLACE, 'puavoCitrixId', [citrix_id.to_json])
      ])
    else
      rlog.info("[#{@request_id}] Have Citrix licensing data in Puavo, updating timestamp")

      citrix_id['last_used'] = make_timestamp()

      user.class.ldap_op(:modify, user.dn, [
        LDAP::Mod.new(LDAP::LDAP_MOD_REPLACE, 'puavoCitrixId', [citrix_id.to_json])
      ])
    end

    citrix_id
  end

  def make_timestamp
    Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S.%L%z')
  end

  def pseudonymize(uuid)
    pseudonym_parts = JSON.parse(File.read('lib/citrix/pseudonym_parts.json'))

    if uuid.match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
      firstname_index = uuid[0..1].to_i(16)
      lastname_index = uuid[34..35].to_i(16)
      [pseudonym_parts['firstnames'][firstname_index], pseudonym_parts['lastnames'][lastname_index]]
    else
      [pseudonym_parts['firstnames'].sample, pseudonym_parts['lastnames'].sample]
    end
  end

end
end

# frozen_string_literal: true

# Interactive OAuth2 client manager. Quite a mess.

require 'securerandom'
require 'io/console'
require 'json'
require 'set'
require 'argon2'
require 'pg'
require 'redis'
require 'optparse'

# --------------------------------------------------------------------------------------------------
# --------------------------------------------------------------------------------------------------
# HELPERS

# Reads a single character from $stdin, no echo
def read_char
  $stdin.echo = false
  $stdin.raw!

  input = $stdin.getc.chr

  if input == "\e"
    input << $stdin.read_nonblock(3) rescue nil
    input << $stdin.read_nonblock(2) rescue nil
  end

  input
ensure
  $stdin.echo = true
  $stdin.cooked!
end

# Reads a string, with default value. If 'echo' is true, the string is not echoed to the screen.
def read_string(prompt, default: nil, allow_empty: false, echo: true)
  $stdin.echo = false unless echo

  begin
    if prompt
      if default
        print "#{clr(:prompt)}#{prompt} #{clr(:default)}[#{default}]: #{clr(:off)}"
      else
        print "#{clr(:prompt)}#{prompt}: #{clr(:off)}"
      end
    end

    s = $stdin.gets
    s = s.strip if s
  rescue Interrupt
    puts ''
    return :cancel
  ensure
    $stdin.echo = true unless echo
  end

  if s.nil? || s.empty?
    allow_empty ? s : default
  else
    s
  end
end

# Reads a yes/no boolean response, with Enter accepting the default
def read_yesno(prompt, default)
  choices = "#{(default == false) ? 'N' : 'n'}/#{(default == true) ? 'Y' : 'y'}"
  print "#{clr(:prompt)}#{prompt} #{clr(:choices)}[#{choices}]: #{clr(:off)}"

  loop do
    c = read_char

    # Ctrl+C
    return :cancel if c.chr == "\u0003"

    # Enter
    if ["\n", "\r"].include?(c.chr)
      puts default ? 'Y' : 'N'
      return default
    end

    if 'nN'.include?(c.chr)
      puts 'N'
      return false
    end

    if 'yY'.include?(c.chr)
      puts 'Y'
      return true
    end
  end
end

# Reads until one of the allowed keys is pressed. Escape can be permitted if needed.
def key_read_loop(allowed_keys, allow_esc)
  loop do
    key = read_char
    return :esc if key == "\e" && allow_esc
    return key if allowed_keys.include?(key)
  end
end

COLORS = {
  prompt: "\e[39m",
  default: "\e[90m",
  choices: "\e[90m",
  separator: "\e[90m",
  action: "\e[96m",
  error: "\e[91m",
  m_prompt: "\e[97m",
  title: "\e[97m",
  m_title: "\e[97m",
  m_letter: "\e[92m",
  m_etitle: "\e[39m",
  maintitle: "\e[97m",
  hint: "\e[90m",
  warning: "\e[93m",
  danger: "\e[91m"
}.freeze

def clr(color)
  if COLORS.include?(color)
    COLORS[color]
  else
    # Reset
    "\e[0m"
  end
end

def print_action(str)
  puts "#{clr(:action)}[#{str}]#{clr(:off)}"
end

def error(str)
  puts "#{clr(:error)}ERROR: #{str}#{clr(:off)}"
end

def generate_password
  password = SecureRandom.alphanumeric(50)
  hasher = Argon2::Password.new(profile: :rfc_9106_low_memory)

  return password, hasher.create(password)
end

def valid_client_id?(id)
  id.is_a?(String) && id.length >= 4 && id.length <= 32 && id.match?(/\A[a-z][a-z0-9_-]*\Z/)
end

# Global database handle
$db = nil

def db
  $db
end

$prod_mode = false

def decode_pg_timestamp(ts)
  PG::TextDecoder::Timestamp.new.decode(ts)
end

def direct_exit
  print_action('Exit')
  exit(0)
end

# --------------------------------------------------------------------------------------------------
# --------------------------------------------------------------------------------------------------
# MENU SYSTEM

class MenuItem
  attr_accessor :title, :go_back
  attr_reader :id, :key, :proc

  def initialize(id, key, title, go_back: false, &proc)
    raise 'the item ID is required' if id.nil?
    raise 'the item key is required' if key.nil?

    @id = id
    @key = key
    @title = title
    @go_back = go_back
    @proc = proc
  end
end

class Menu
  attr_reader :id, :title, :items

  def initialize(id, title)
    @id = id
    @title = title
    @item_id = Set.new
    @item_keys = Set.new
    @items = []
    @esc_exit = false
  end

  def permit_esc_exit
    @esc_exit = true
  end

  def add_item(item)
    raise "Menu item \"#{item.id}\" already exists in menu \"#{id}\"" if @item_id.include?(item.id)
    raise "Duplicate key \"#{item.key}\" for menu item \"#{item.id}\"" if @item_keys.include?(item.key)

    @item_id << item.id
    @item_keys << item.key
    @items << item
  end

  def <<(item)
    add_item(item)
  end

  def run
    loop do
      puts "#{clr(:separator)}#{'-' * 50}#{clr(:off)}"
      puts "#{clr(:m_title)}#{title}#{clr(:off)}"

      @items.each do |item|
        puts "  #{clr(:m_letter)}#{item.key}#{clr(:off)}: #{clr(:m_etitle)}#{item.title}#{clr(:off)}"
      end

      print "#{clr(:m_prompt)}Select: #{clr(:off)}"

      selection = key_read_loop(@item_keys, @esc_exit)

      if selection == :esc
        puts ''
        print_action('Exit')
        db.close
        exit(0)
      end

      # Find the item
      puts "#{clr(:m_letter)}#{selection}#{clr(:off)}"
      item = @items.find { |i| i.key == selection }

      # Go back to the upper level (if nested menus)
      if item.go_back
        print_action('Going back')
        break
      end

      # Run the menu item proc
      if item.proc
        item.proc.call(item)
      else
        puts "[Internal error: No proc associated with menu item \"#{item.title}\"]"
      end
    end
  end
end

# --------------------------------------------------------------------------------------------------
# --------------------------------------------------------------------------------------------------
# LOGIN CLIENTS

def list_login_clients
  puts "#{clr(:title)}Listing existing login clients#{clr(:off)}"

  rows = db.exec('SELECT * FROM login_clients')
  array_decoder = PG::TextDecoder::Array.new

  if rows.count == 0
    puts 'No login clients found'
    return
  end

  rows.each_with_index do |row, i|
    puts "[Client #{i + 1}/#{rows.count}]"
    puts "\tClient ID............: #{row['client_id'].inspect}"
    puts "\tEnabled..............: #{(row['enabled'] == 't') ? 'Yes' : 'No'}"
    puts "\tPuavo service DN.....: #{row['puavo_service_dn'].inspect}"
    puts "\tAllowed redirect URIs:"

    uris = array_decoder.decode(row['allowed_redirects'])

    uris.each_with_index do |uri, j|
      puts "\t\t[#{j + 1}/#{uris.count}] #{uri.inspect}"
    end

    puts "\tAllowed scopes.......:"

    scopes = array_decoder.decode(row['allowed_scopes'])

    scopes.each_with_index do |scope, j|
      puts "\t\t[#{j + 1}/#{scopes.count}] #{scope.inspect}"
    end

    puts "\tCreated..............: #{decode_pg_timestamp(row['created'])}"
    puts "\tModified.............: #{decode_pg_timestamp(row['modified'])}"
  end
end

def get_existing_login_clients
  db.exec(
    'SELECT client_id FROM login_clients'
  ).to_set do |row|
    row['client_id']
  end
end

def format_login_client_id(client)
  "Rename client (currently \"#{client['client_id']}\")"
end

def rename_login_client(client, existing)
  puts "#{clr(:hint)}The client ID can only contain a-z0-9_- and it must start with a letter. It's length must be between 4 and 32.#{clr(:off)}"

  new_id = read_string(
    'Enter the new client ID (Ctrl+C to cancel)',
    default: client['client_id']
  )

  if new_id == :cancel
    print_action('Cancelled')
    return false
  end

  if new_id.empty?
    # Can this even happen? "allow_empty" is not used.
    error('The client ID cannot be empty')
    return false
  end

  unless valid_client_id?(new_id)
    error('The client ID is not valid')
    return false
  end

  if new_id == client['client_id']
    print_action('Client ID not changed')
    return false
  end

  # Duplicate name?
  if existing.include?(new_id)
    error('The new client ID is already in use')
    return false
  end

  db.exec_params(
    'UPDATE login_clients SET client_id = $2, modified = $3 WHERE client_id = $1',
    [client['client_id'], new_id, Time.now.utc]
  )

  client['client_id'] = new_id
  print_action("Client ID changed to \"#{new_id}\"")
  true
end

def format_login_client_enabled(client)
  (client['enabled'] == 't') ? 'Disable (currently enabled)' : 'Enable (currently disabled)'
end

def enable_login_client(client)
  if client['enabled'] == 't'
    db.exec_params(
      'UPDATE login_clients SET enabled = false, modified = $2 WHERE client_id = $1',
      [client['client_id'], Time.now.utc]
    )

    client['enabled'] = 'f'
    print_action('Client disabled')
  else
    db.exec_params(
      'UPDATE login_clients SET enabled = true, modified = $2 WHERE client_id = $1',
      [client['client_id'], Time.now.utc]
    )

    client['enabled'] = 't'
    print_action('Client enabled')
  end
end

def format_login_client_service_dn(client)
  "Change Puavo external service DN (currently \"#{client['puavo_service_dn']}\")"
end

def change_login_client_puavo_service_dn(client)
  new_dn = read_string(
    'Enter new Puavo external service DN for this client (Ctrl+C to cancel)',
    default: client['puavo_service_dn']
  )

  if new_dn == :cancel
    print_action('Cancelled')
    return false
  end

  if new_dn.empty?
    error('The service DN cannot be empty')
    return false
  end

  if new_dn == client['puavo_service_dn']
    print_action('Service DN not changed')
    return false
  end

  db.exec_params(
    'UPDATE login_clients SET puavo_service_dn = $2, modified = $3 WHERE client_id = $1',
    [client['client_id'], new_dn, Time.now.utc]
  )

  client['puavo_service_dn'] = new_dn
  print_action("Puavo external service DN changed to \"#{new_dn}\"")
  true
end

def format_login_client_redirect_uris(client)
  "Change redirect URIs (currently \"#{PG::TextDecoder::Array.new.decode(client['allowed_redirects']).join(' ')}\")"
end

def change_login_client_redirect_uris(client)
  decoder = PG::TextDecoder::Array.new
  encoder = PG::TextEncoder::Array.new

  new_uris = read_string(
    'Enter a space-delimited list of redirect URIs for this client (Ctrl+C to cancel)',
    default: decoder.decode(client['allowed_redirects']).join(' ')
  )

  if new_uris == :cancel
    print_action('Cancelled')
    return false
  end

  new_uris = new_uris.split

  if new_uris.empty?
    # Can this even happen? "allow_empty" is not used.
    error('You need to specify at least one redirect URI')
    return false
  end

  parts = new_uris
  new_uris = encoder.encode(new_uris)

  if new_uris == client['allowed_redirects']
    print_action('Redirect URIs not changed')
    return false
  end

  db.exec_params(
    'UPDATE login_clients SET allowed_redirects = $2, modified = $3 WHERE client_id = $1',
    [client['client_id'], new_uris, Time.now.utc]
  )

  client['allowed_redirects'] = new_uris
  print_action("Redirect URIs changed to \"#{parts.join(' ')}\"")
  true
end

def format_login_client_scopes(client)
  "Change scopes (currently \"#{PG::TextDecoder::Array.new.decode(client['allowed_scopes']).join(' ')}\")"
end

def change_login_client_scopes(client)
  new_scopes = read_string(
    'Enter a space-delimited list of scopes for this client (Ctrl+C to cancel)',
    default: PG::TextDecoder::Array.new.decode(client['allowed_scopes']).join(' ')
  )

  if new_scopes == :cancel
    print_action('Cancelled')
    return false
  end

  new_scopes = new_scopes.split

  if new_scopes.empty?
    # Can this even happen? "allow_empty" is not used.
    error('You need to specify at least one scope')
    return false
  end

  parts = new_scopes
  new_scopes = PG::TextEncoder::Array.new.encode(new_scopes)

  if new_scopes == client['allowed_scopes']
    print_action('Scopes not changed')
    return false
  end

  db.exec_params(
    'UPDATE login_clients SET allowed_scopes = $2, modified = $3 WHERE client_id = $1',
    [client['client_id'], new_scopes, Time.now.utc]
  )

  client['allowed_scopes'] = new_scopes
  print_action("Scopes changed to \"#{parts.join(' ')}\"")
  true
end

def edit_login_client
  existing = get_existing_login_clients()
  puts "#{clr(:hint)}Existing login clients: #{existing.to_a.sort.join(' ')}#{clr(:off)}"

  client_id = nil
  client = nil

  loop do
    client_id = read_string('Enter the ID of the login client you want to edit (press Ctrl+C to cancel)')

    if client_id == :cancel
      print_action('Cancelled')
      return
    end

    client = db.exec_params(
      'SELECT * FROM login_clients WHERE client_id = $1',
      [client_id]
    )

    break if client.count == 1

    error('No login client found with that ID')
  end

  client = client[0].to_h

  edit_menu = Menu.new(:edit_login_client, 'Main menu > Login clients > Edit client')

  # Client ID
  edit_menu << MenuItem.new(:rename, 'r', format_login_client_id(client)) do |item|
    existing = get_existing_login_clients()

    if rename_login_client(client, existing)
      item.title = format_login_client_id(client)
    end
  end

  # Enabled?
  edit_menu << MenuItem.new(:enable, 'e', format_login_client_enabled(client)) do |item|
    enable_login_client(client)
    item.title = format_login_client_enabled(client)
  end

  # Puavo Service DN
  edit_menu << MenuItem.new(:puavo_service, 'p', format_login_client_service_dn(client)) do |item|
    if change_login_client_puavo_service_dn(client)
      item.title = format_login_client_service_dn(client)
    end
  end

  # Redirect URIs
  edit_menu << MenuItem.new(:uris, 'u', format_login_client_redirect_uris(client)) do |item|
    if change_login_client_redirect_uris(client)
      item.title = format_login_client_redirect_uris(client)
    end
  end

  # Allowed scopes
  edit_menu << MenuItem.new(:scopes, 's', format_login_client_scopes(client)) do |item|
    if change_login_client_scopes(client)
      item.title = format_login_client_scopes(client)
    end
  end

  edit_menu << MenuItem.new(:back, 'b', 'Go back to the previous menu', go_back: true)
  edit_menu << MenuItem.new(:exit, 'x', 'Exit the script') { direct_exit }

  edit_menu.run
end

def new_login_client
  existing = get_existing_login_clients()
  puts "#{clr(:title)}Creating a new login client. Press Ctrl+C at any time to cancel.#{clr(:off)}"
  puts "#{clr(:hint)}Existing login clients: #{existing.to_a.sort.join(' ')}#{clr(:off)}"
  puts "#{clr(:hint)}The client ID can only contain a-z0-9_- and it must start with a letter. It's length must be between 4 and 32.#{clr(:off)}"

  encoder = PG::TextEncoder::Array.new

  # Client ID
  client_id = nil

  loop do
    client_id = read_string('Unique client ID')

    if client_id == :cancel
      print_action('Cancelled')
      return
    end

    unless valid_client_id?(client_id)
      error('The client ID is not valid')
      next
    end

    existing = get_existing_login_clients()
    break unless existing.include?(client_id)

    error('This client ID is already in use. Choose another.')
  end

  # Enabled?
  enabled = read_yesno('Enabled by default?', false)

  if enabled == :cancel
    print_action('Cancelled')
    return
  end

  # Puavo service DN
  puavo_service_dn = nil

  loop do
    puavo_service_dn = read_string('Puavo external service DN')

    if puavo_service_dn == :cancel
      print_action('Cancelled')
      return
    end

    break unless puavo_service_dn.nil?
  end

  # Allowed redirects
  redirects = nil

  loop do
    redirects = read_string('A space-separated list of allowed redirect URIs')

    if redirects == :cancel
      print_action('Cancelled')
      return
    end

    if redirects.nil?
      error('The redirects list cannot be empty')
      next
    end

    redirects = redirects.split

    if redirects.empty?
      error('The redirects list cannot be empty')
    else
      redirects = encoder.encode(redirects)
      break
    end
  end

  # Allowed scopes
  scopes = nil

  loop do
    scopes = read_string('A space-separated list of allowed scopes')

    if scopes == :cancel
      print_action('Cancelled')
      return
    end

    if scopes.nil?
      error('The scopes list cannot be empty')
      next
    end

    scopes = scopes.split

    if scopes.empty?
      error('The scopes list cannot be empty')
    else
      scopes = encoder.encode(scopes)
      break
    end
  end

  # Create the client
  puts "#{clr(:action)}Creating the client...#{clr(:off)}"
  now = Time.now.utc

  db.exec_params(
    'INSERT INTO login_clients (client_id, enabled, puavo_service_dn, allowed_redirects, ' \
    'allowed_scopes, created, modified) VALUES ($1, $2, $3, $4, $5, $6, $7)',
    [client_id, enabled, puavo_service_dn, redirects, scopes, now, now]
  )

  puts "#{clr(:action)}Done!#{clr(:off)}"
end

def delete_login_client
  puts "#{clr(:danger)}Deleting a login client. Press Ctrl+C to cancel.#{clr(:off)}"

  client_id = read_string('Client ID to be deleted')

  if client_id == :cancel
    print_action('Cancelled')
    return
  end

  # TODO: There's no verification if the ID was correct
  db.exec_params(
    'DELETE FROM login_clients WHERE client_id = $1',
    [client_id]
  )

  print_action('Client deleted')
end

# Deletes the test login clients created during puavo-rest tests
# (they are not automatically removed afterwards)
def delete_test_login_clients
  test_clients = db.exec_params(
    "SELECT client_id FROM login_clients WHERE client_id LIKE 'test_login_%'"
  ).collect do |row|
    row['client_id']
  end

  if test_clients.empty?
    print_action('No test clients found')
    return
  end

  puts "Have #{test_clients.count} test clients: #{test_clients.inspect}"

  unless read_yesno('Proceed with deletion?', false)
    print_action('Test clients not deleted')
    return
  end

  db.exec("DELETE FROM login_clients WHERE client_id LIKE 'test_login_%'")
  print_action('Test clients deleted')
end

def login_clients_menu
  login_menu = Menu.new(:login_clients_menu, 'Main menu > Login clients')

  login_menu << MenuItem.new(:list_login, 'l', 'List clients') { list_login_clients }
  login_menu << MenuItem.new(:new_login, 'n', 'New client') { new_login_client }
  login_menu << MenuItem.new(:edit_login, 'e', 'Edit client') { edit_login_client }
  login_menu << MenuItem.new(:delete_login, 'd', 'Delete client') { delete_login_client }
  login_menu << MenuItem.new(:delete_test, 't', 'Delete OAuth2 test clients') { delete_test_login_clients } #unless $prod_mode
  login_menu << MenuItem.new(:back, 'b', 'Go back to the previous menu', go_back: true)
  login_menu << MenuItem.new(:exit, 'x', 'Exit the script') { direct_exit }

  login_menu.run
end

# --------------------------------------------------------------------------------------------------
# --------------------------------------------------------------------------------------------------
# TOKEN CLIENTS

def list_token_clients
  puts "#{clr(:title)}Listing existing token clients#{clr(:off)}"

  rows = db.exec_params('SELECT * FROM token_clients')
  array_decoder = PG::TextDecoder::Array.new

  if rows.count == 0
    puts 'No token clients found'
    return
  end

  rows.each_with_index do |row, i|
    puts "[Client #{i + 1}/#{rows.count}]"
    puts "\tClient ID............: #{row['client_id'].inspect}"
    puts "\tEnabled..............: #{row['enabled'] == 't' ? 'Yes' : 'No'}"
    puts "\tExpires in...........: #{row['expires_in']} seconds"
    puts "\tAssociated LDAP DN...: #{row['ldap_user_dn'].nil? ? '<Unset>' : row['ldap_user_dn']}"

    puts "\tAllowed scopes.......:"

    scopes = array_decoder.decode(row['allowed_scopes'])

    scopes.each_with_index do |scope, j|
      puts "\t\t[#{j + 1}/#{scopes.count}] #{scope.inspect}"
    end

    puts "\tAllowed endpoints....:"

    endpoints = array_decoder.decode(row['allowed_endpoints'] || '{}')

    if endpoints.empty?
      puts "\t\t<None, the token is valid in any endpoint that accepts the scopes>"
    else
      endpoints.each_with_index do |endpoint, j|
        puts "\t\t[#{j + 1}/#{endpoints.count}] #{endpoint.inspect}"
      end
    end

    puts "\tAllowed organisations:"

    organisations = array_decoder.decode(row['allowed_organisations'] || '{}')

    if organisations.empty?
      puts "\t\t<None, the generated tokens are valid everywhere>"
    else
      organisations.each_with_index do |org, j|
        puts "\t\t[#{j + 1}/#{organisations.count}] #{org.inspect}"
      end
    end

    puts "\tCreated..............: #{decode_pg_timestamp(row['created'])}"
    puts "\tModified.............: #{decode_pg_timestamp(row['modified'])}"
    puts "\tPassword changed.....: #{decode_pg_timestamp(row['password_changed'])}"
  end
end

def get_existing_token_clients
  db.exec(
    'SELECT client_id FROM token_clients'
  ).to_set do |row|
    row['client_id']
  end
end

def format_token_client_id(client)
  "Rename client (currently \"#{client['client_id']}\")"
end

def rename_token_client(client)
  puts "#{clr(:hint)}The client ID can only contain a-z0-9_- and it must start with a letter. It's length must be between 4 and 32.#{clr(:off)}"

  new_id = read_string(
    'Enter new ID for this client (Ctrl+C to cancel)',
    default: client['client_id']
  )

  if new_id == :cancel
    print_action('Cancelled')
    return false
  end

  if new_id.empty?
    # Can this even happen? "allow_empty" is not used.
    error('The ID cannot be empty')
    return false
  end

  unless valid_client_id?(new_id)
    error('The client ID is not valid')
    return false
  end

  if new_id == client['client_id']
    print_action('Client ID not changed')
    return false
  end

  # Duplicate name?
  existing = get_existing_token_clients()

  if existing.include?(new_id)
    error('The new ID is already in use')
    return false
  end

  db.exec_params(
    'UPDATE token_clients SET client_id = $2, modified = $3 WHERE client_id = $1',
    [client['client_id'], new_id, Time.now.utc]
  )

  client['client_id'] = new_id
  print_action("Client ID changed to \"#{new_id}\"")
  true
end

def format_token_client_enabled(client)
  (client['enabled'] == 't') ? 'Disable (currently enabled)' : 'Enable (currently disabled)'
end

def enable_token_client(client)
  if client['enabled'] == 't'
    client['enabled'] = 'f'

    db.exec_params(
      'UPDATE token_clients SET enabled = false, modified = $2 WHERE client_id = $1',
      [client['client_id'], Time.now.utc]
    )

    print_action('Client disabled')
  else
    client['enabled'] = 't'

    db.exec_params(
      'UPDATE token_clients SET enabled = true, modified = $2 WHERE client_id = $1',
      [client['client_id'], Time.now.utc]
    )

    print_action('Client enabled')
  end
end

def format_token_client_expires_in_time(client)
  "Set the \"expires in\" time (currently #{client['expires_in']} seconds)"
end

def change_token_client_expires_in_time(client)
  puts "#{clr(:hint)}The default time is 3600 seconds. Remember that long-lived tokens can pose a serious security hazard.#{clr(:off)}"

  new_time = read_string('Enter new "expires in" time (press Ctrl+C to cancel)')

  if new_time == :cancel || new_time.nil? || new_time.empty?
    print_action('Cancelled')
    return false
  end

  begin
    new_time = new_time.to_i
  rescue StandardError
    error("Can't interpret that as an integer")
    return false
  end

  db.exec_params(
    'UPDATE token_clients SET expires_in = $2, modified = $3 WHERE client_id = $1',
    [client['client_id'], new_time, Time.now.utc]
  )

  client['expires_in'] = new_time
  print_action("\"Expires in\" time changed to #{new_time} seconds")
  true
end

def format_token_client_ldap_user_dn(client)
  if client['ldap_user_dn'].nil?
    "Set the LDAP user DN (currently unset, the client will not work)"
  else
    "Set the LDAP user DN (currently #{client['ldap_user_dn'].inspect})"
  end
end

def change_token_client_ldap_user_dn(client)
  new_dn = read_string(
    'Enter an LDAP user DN (leave empty to set it to NULL)',
    allow_empty: true
  )

  if new_dn == :cancel
    print_action('Cancelled')
    return false
  end

  if new_dn.nil? || new_dn.empty?
    db.exec_params(
      'UPDATE token_clients SET ldap_user_dn = NULL, modified = $2 WHERE client_id = $1',
      [client['client_id'], Time.now.utc]
    )

    client['ldap_user_dn'] = nil
    print_action('User DN cleared, the client will not work')
    return true
  end

  if new_dn == client['ldap_user_dn']
    print_action('LDAP user DN not changed')
    return false
  end

  db.exec_params(
    'UPDATE token_clients SET ldap_user_dn = $2, modified = $3 WHERE client_id = $1',
    [client['client_id'], new_dn, Time.now.utc]
  )

  client['ldap_user_dn'] = new_dn
  print_action("LDAP user DN changed to \"#{new_dn}\"")
  true
end

def change_token_client_password(client)
  new_password, hashed_password = generate_password()

  db.exec_params(
    'UPDATE token_clients SET client_password = $2, modified = $3, password_changed = $3 WHERE client_id = $1',
    [client['client_id'], hashed_password, Time.now]
  )

  puts("#{clr(:action)}New password set to\n\n    #{new_password}\n\n" \
       "Please copy-paste it to somewhere safe now, as it cannot be recovered later!#{clr(:off)}")
end

def format_token_client_scopes(client)
  "Change scopes (currently \"#{PG::TextDecoder::Array.new.decode(client['allowed_scopes']).join(' ')}\")"
end

def change_token_client_scopes(client)
  new_scopes = read_string(
    'Enter a space-delimited list of scopes for this client (Ctrl+C to cancel)',
    default: PG::TextDecoder::Array.new.decode(client['allowed_scopes']).join(' ')
  )

  if new_scopes == :cancel
    print_action('Cancelled')
    return false
  end

  new_scopes = new_scopes.split

  if new_scopes.empty?
    error('You need to specify at least one scope')
    return false
  end

  parts = new_scopes

  new_scopes = PG::TextEncoder::Array.new.encode(new_scopes)

  if new_scopes == client['allowed_scopes']
    print_action('Scopes not changed')
    return false
  end

  db.exec_params(
    'UPDATE token_clients SET allowed_scopes = $2, modified = $3 WHERE client_id = $1',
    [client['client_id'], new_scopes, Time.now.utc]
  )

  client['allowed_scopes'] = new_scopes
  print_action("Scopes changed to \"#{parts.join(' ')}\"")
  true
end

def format_token_client_endpoints(client)
  endpoints = PG::TextDecoder::Array.new.decode(client['allowed_endpoints'])

  if endpoints.nil?
    'Change endpoints (currently all endpoints that accept the scopes are allowed)'
  else
    "Change endpoints (currently \"#{endpoints.join(' ')}\")"
  end
end

def change_token_client_endpoints(client)
  new_endpoints = read_string(
    'Enter a space-delimited list of endpoints for this client (Ctrl+C to cancel)',
    allow_empty: true
  )

  if new_endpoints == :cancel
    print_action('Cancelled')
    return false
  end

  if new_endpoints.nil? || new_endpoints.empty?
    db.exec_params(
      'UPDATE token_clients SET allowed_endpoints = NULL, modified = $2 WHERE client_id = $1',
      [client['client_id'], Time.now.utc]
    )

    client['allowed_endpoints'] = nil
    print_action('Endpoints cleared, everything is now permitted')
    return true
  end

  new_endpoints = new_endpoints.split
  new_endpoints = nil if new_endpoints.empty?
  parts = new_endpoints

  new_endpoints = PG::TextEncoder::Array.new.encode(new_endpoints)

  if new_endpoints == client['allowed_endpoints']
    print_action('Endpoints not changed')
    return false
  end

  db.exec_params(
    'UPDATE token_clients SET allowed_endpoints = $2, modified = $3 WHERE client_id = $1',
    [client['client_id'], new_endpoints, Time.now.utc]
  )

  client['allowed_endpoints'] = new_endpoints
  print_action("Endpoints changed to \"#{parts.join(' ')}\"")
  true
end

def format_token_client_organisations(client)
  organisations = PG::TextDecoder::Array.new.decode(client['allowed_organisations'])

  if organisations.nil?
    'Change organisations (currently all organisations are allowed)'
  else
    "Change organisations (currently \"#{organisations.join(' ')}\")"
  end
end

def change_token_client_organisations(client)
  new_organisations = read_string(
    'Enter a space-delimited list of organisations for this client (Ctrl+C to cancel)',
    allow_empty: true
  )

  if new_organisations == :cancel
    print_action('Cancelled')
    return false
  end

  if new_organisations.nil? || new_organisations.empty?
    db.exec_params(
      'UPDATE token_clients SET allowed_organisations = NULL, modified = $2 WHERE client_id = $1',
      [client['client_id'], Time.now.utc]
    )

    client['allowed_organisations'] = nil
    print_action('Organisations cleared, all organisations are permitted')
    return true
  end

  new_organisations = new_organisations.split
  new_organisations = nil if new_organisations.empty?
  parts = new_organisations

  new_organisations = PG::TextEncoder::Array.new.encode(new_organisations)

  if new_organisations == client['allowed_organisations']
    print_action('[Organisations not changed]')
    return false
  end

  db.exec_params(
    'UPDATE token_clients SET allowed_organisations = $2, modified = $3 WHERE client_id = $1',
    [client['client_id'], new_organisations, Time.now.utc]
  )

  client['allowed_organisations'] = new_organisations
  print_action("Organisations changed to \"#{parts.join(' ')}\"")
  true
end

def edit_token_client
  existing = get_existing_token_clients()
  puts "#{clr(:hint)}Existing token clients: #{existing.to_a.sort.join(' ')}#{clr(:off)}"

  client_id = nil
  client = nil

  loop do
    client_id = read_string('Enter the ID of the token client you want to edit (press Ctrl+C to cancel)')

    if client_id == :cancel
      print_action('Cancelled')
      return
    end

    client = db.exec_params(
      'SELECT * FROM token_clients WHERE client_id = $1',
      [client_id]
    )

    break if client.count == 1

    error('No token client found with that ID')
  end

  client = client[0].to_h

  edit_menu = Menu.new(:edit_login_client, 'Main menu > Token clients > Edit client')

  # Client ID
  edit_menu << MenuItem.new(:rename, 'r', format_token_client_id(client)) do |item|
    if rename_token_client(client)
      item.title = format_token_client_id(client)
    end
  end

  # Enabled?
  edit_menu << MenuItem.new(:enable, 'e', format_token_client_enabled(client)) do |item|
    enable_token_client(client)
    item.title = format_token_client_enabled(client)
  end

  # Expiration time
  edit_menu << MenuItem.new(:expiration, 't', format_token_client_expires_in_time(client)) do |item|
    if change_token_client_expires_in_time(client)
      item.title = format_token_client_expires_in_time(client)
    end
  end

  # LDAP user DN
  edit_menu << MenuItem.new(:ldap_user_dn, 'l', format_token_client_ldap_user_dn(client)) do |item|
    if change_token_client_ldap_user_dn(client)
      item.title = format_token_client_ldap_user_dn(client)
    end
  end

  # Generate new password
  edit_menu << MenuItem.new(:password, 'p', 'Generate new password') do
    change_token_client_password(client)
  end

  # Allowed scopes
  edit_menu << MenuItem.new(:scopes, 's', format_token_client_scopes(client)) do |item|
    if change_token_client_scopes(client)
      item.title = format_token_client_scopes(client)
    end
  end

  # Allowed endpoints. This list can be empty.
  edit_menu << MenuItem.new(:endpoints, 'd', format_token_client_endpoints(client)) do |item|
    if change_token_client_endpoints(client)
      item.title = format_token_client_endpoints(client)
    end
  end

  # Allowed organisations. This list can be empty.
  edit_menu << MenuItem.new(:organisations, 'o', format_token_client_organisations(client)) do |item|
    if change_token_client_organisations(client)
      item.title = format_token_client_organisations(client)
    end
  end

  edit_menu << MenuItem.new(:back, 'b', 'Go back to the previous menu', go_back: true)
  edit_menu << MenuItem.new(:exit, 'x', 'Exit the script') { direct_exit }

  edit_menu.run
end

def new_token_client
  existing = get_existing_token_clients()
  encoder = PG::TextEncoder::Array.new

  puts "#{clr(:title)}Creating a new access token client. Press Ctrl+C at any time to cancel.#{clr(:off)}"
  puts "#{clr(:hint)}Existing token clients: #{existing.to_a.sort.join(' ')}#{clr(:off)}" unless existing.empty?
  puts "#{clr(:hint)}The client ID can only contain a-z0-9_- and it must start with a letter. It's length must be between 4 and 32.#{clr(:off)}"

  # Client ID (loop until we have a unique ID)
  client_id = nil

  loop do
    client_id = read_string('Unique client ID')

    if client_id == :cancel
      print_action('Cancelled')
      return
    end

    unless valid_client_id?(client_id)
      error('The client ID is not valid')
      next
    end

    existing = get_existing_token_clients()
    break unless existing.include?(client_id)

    error('This client ID is already in use. Choose another.')
  end

  # Enabled?
  enabled = read_yesno('Enabled by default?', false)

  if enabled == :cancel
    print_action('Cancelled')
    return
  end

  # Allowed scopes
  scopes = nil

  loop do
    scopes = read_string('A space-separated list of allowed scopes')

    if scopes == :cancel
      print_action('Cancelled')
      return
    end

    if scopes.nil?
      error('The scopes list cannot be empty')
      next
    end

    scopes = scopes.split

    if scopes.empty?
      error('The scopes list cannot be empty')
    else
      scopes = encoder.encode(scopes)
      break
    end
  end

  # Allowed endpoints
  endpoints = read_string('A space-separated list of allowed puavo-rest endpoints (can be empty)')

  if endpoints == :cancel
    print_action('Cancelled')
    return
  end

  if endpoints
    endpoints = encoder.encode(endpoints.split)
  else
    endpoints = nil
  end

  # Allowed organisations
  organisations = read_string('A space-separated list of allowed organisation domains (can be empty)')

  if organisations == :cancel
    print_action('Cancelled')
    return
  end

  if organisations
    organisations = encoder.encode(organisations.split)
  else
    organisations = nil
  end

  # Create a random password
  password, hashed_password = generate_password()
  puts("#{clr(:action)}Client password set to\n\n    #{password}\n\nPlease copy-paste it to somewhere safe now, as it cannot be recovered later.#{clr(:off)}")

  # Create the client
  puts "#{clr(:action)}Creating the client...#{clr(:off)}"

  now = Time.now.utc

  db.exec_params(
    'INSERT INTO token_clients (client_id, client_password, enabled, ' \
    'allowed_scopes, allowed_endpoints, allowed_organisations, created, ' \
    'modified, password_changed) VALUES($1, $2, $3, $4, $5, $6, $7, $8, $9)',
    [client_id, hashed_password, enabled, scopes, endpoints, organisations, now, now, now]
  )

  puts "#{clr(:action)}Done!#{clr(:off)}"
end

def delete_token_client
  puts "#{clr(:danger)}Deleting an access token client. Press Ctrl+C to cancel.#{clr(:off)}"

  client_id = read_string('Client ID to be deleted')

  if client_id == :cancel
    print_action('Cancelled')
    return
  end

  # TODO: There's no verification if the ID was correct
  db.exec_params(
    'DELETE FROM token_clients WHERE client_id = $1',
    [client_id]
  )

  print_action('Client deleted')
end

# Deletes the test token clients created during puavo-rest tests
# (they are not automatically removed afterwards)
def delete_test_token_clients
  test_clients = db.exec_params(
    "SELECT client_id FROM token_clients WHERE client_id LIKE 'test_client_%'"
  ).collect do |row|
    row['client_id']
  end

  if test_clients.empty?
    print_action('No test clients found')
    return
  end

  puts "Have #{test_clients.count} test clients: #{test_clients.inspect}"

  unless read_yesno('Proceed with deletion?', false)
    print_action('Test clients not deleted')
    return
  end

  db.exec("DELETE FROM token_clients WHERE client_id LIKE 'test_client_%'")
  print_action('Test clients deleted')
end

def token_clients_menu
  menu = Menu.new(:login_clients_menu, 'Main menu > Token clients')

  menu << MenuItem.new(:list_token, 'l', 'List clients') { list_token_clients }
  menu << MenuItem.new(:new_token, 'n', 'New client') { new_token_client }
  menu << MenuItem.new(:edit_token, 'e', 'Edit client') { edit_token_client }
  menu << MenuItem.new(:delete_token, 'd', 'Delete client') { delete_token_client }
  menu << MenuItem.new(:delete_test, 't', 'Delete OAuth2 test clients') { delete_test_token_clients } unless $prod_mode
  menu << MenuItem.new(:back, 'b', 'Go back to the previous menu', go_back: true)
  menu << MenuItem.new(:exit, 'x', 'Exit the script') { direct_exit }

  menu.run
end

# --------------------------------------------------------------------------------------------------
# --------------------------------------------------------------------------------------------------
# MAIN

# Parse the command line
BANNER = \
"Creates and edits Puavo's OAuth2 clients

By default, the script runs in puavo-standalone mode, ie. it uses the
standalone database and standalone password. If you need to run in
production mode, use --prod to enable it, then the options below to
specify the location of the production database.

"

# The default settings for puavo-standalone environment (not production!)
args = {
  prod: false,
  db_host: '127.0.0.1',
  db_port: 5432,
  db_user: 'standalone_user',
  db_password: 'standalone_password'
}

parser = OptionParser.new(BANNER)

parser.on('-p', '--prod', 'Enable production mode') do
  args[:prod] = true
end

parser.on('-h', '--host address', 'Database host address (default is "127.0.0.1")') do |db_host|
  args[:db_host] = db_host
end

parser.on('-p', '--port number', 'Database port number (default is 5432)') do |db_port|
  args[:db_port] = db_port.to_i
end

parser.on('-u', '--user name', 'Database user name (default is "standalone_user")') do |db_user|
  args[:db_user] = db_user
end

parser.parse! unless ARGV.empty?

puts "#{clr(:maintitle)}#{'=' * 60}"
puts 'Welcome to the OAuth2 login and token clients management'
puts 'script version 0.5. Use the --help command line switch to'
puts 'see usage instructions.'
puts "#{clr(:danger)}Please remember that all changes take place instantly;"
puts 'there is no separate "save" command!'
puts "#{clr(:maintitle)}#{'=' * 60}#{clr(:off)}"

# Read the production database password
if args[:prod]
  password = read_string("Enter the production database password (won't echo; press Ctrl+C to cancel)", echo: false)

  if password == :cancel
    print_action('Cancelled, exiting')
    exit(1)
  end

  args[:db_password] = password
  puts ''
end

if args[:prod]
  puts "#{clr(:warning)}Running in PRODUCTION mode, using the real database#{clr(:off)}"
  $prod_mode = true
else
  puts 'Running in STANDALONE mode'
end

# Connect to the database
begin
  $db = PG.connect(
    hostaddr: args[:db_host],
    port: args[:db_port],
    dbname: 'oauth2',
    user: args[:db_user],
    password: args[:db_password]
  )
rescue StandardError => e
  error("Unable to connect to the database: #{e}")
  exit(1)
end

num_login = db.exec('SELECT COUNT(*) FROM login_clients')[0]['count']
num_token = db.exec('SELECT COUNT(*) FROM token_clients')[0]['count']

puts "The database has #{num_login} login clients and #{num_token} token clients."

main_menu = Menu.new(:main_menu, 'Main menu')

main_menu << MenuItem.new(:list_login, 'l', 'List and edit login clients') { login_clients_menu }
main_menu << MenuItem.new(:list_token, 'a', 'List and edit access token clients') { token_clients_menu }

main_menu << MenuItem.new(:exit, 'x', 'Exit (Esc also works)') do
  print_action('Exit')
  db.close
  exit(0)
end

main_menu.permit_esc_exit
main_menu.run

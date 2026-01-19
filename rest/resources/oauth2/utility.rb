# frozen_string_literal: true

# Various OAuth2 utility things

module PuavoRest
module OAuth2

CLIENT_ID_VALIDATOR = /\A[a-z][a-z0-9_-]*\Z/.freeze

def self.valid_client_id?(id)
  id.is_a?(String) && id.length >= 4 && id.length <= 32 && id.match?(CLIENT_ID_VALIDATOR)
end

# Handles connections to the OAuth2 client database. Note the lack of exception handling;
# the caller must deal with them.
class ClientDatabase
  def initialize
    db_config = CONFIG['oauth2']['client_database']

    @db = PG.connect(hostaddr: db_config['host'],
                     port: db_config['port'],
                     dbname: db_config['database'],
                     user: db_config['user'],
                     password: db_config['password'])
  end

  def close
    if @db
      @db.close
      @db = nil
    end
  end

  def get_login_client(client_id)
    get_client_by_id(client_id, :login)
  end

  def get_token_client(client_id)
    get_client_by_id(client_id, :token)
  end

  private

  def get_client_by_id(client_id, type)
    # exec_params doesn't support parameterizing the table name
    table = (type == :login) ? 'login_clients' : 'token_clients'
    rows = @db.exec_params("SELECT * FROM #{table} WHERE client_id = $1;", [client_id])
    return nil if rows.count != 1

    client_config = rows[0].to_hash

    # Convert certain columns into arrays
    array_decoder = PG::TextDecoder::Array.new

    %w[allowed_redirects allowed_scopes allowed_endpoints allowed_organisations].each do |key|
      next unless client_config.include?(key)
      client_config[key] = array_decoder.decode(client_config[key])
    end

    # Turn the enabled flag into an actual boolean
    client_config['enabled'] = client_config['enabled'] == 't'

    # Retrieve all enabled authentication credentials for this client. We know the client ID is valid.
    client_config.delete('client_password')
    auth = @db.exec_params("SELECT * FROM client_authentication WHERE client_id = $1 AND enabled = true;", [client_id]).to_a

    auth.map do |a|
      a.delete('client_id')
      a.delete('enabled')
    end

    client_config['client_authentication'] = auth

    client_config.freeze
  end
end   # class ClientDatabase

end   # module OAuth2
end   # module PuavoRest

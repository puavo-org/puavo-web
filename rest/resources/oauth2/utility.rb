# frozen_string_literal: true

# Various OAuth2 utility things

module PuavoRest
module OAuth2

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

  # Retrieves the client configuration from the database using the specified client ID.
  # 'type' must be either :login or :token, depending on the client type.
  def get_client_by_id(request_id, client_id, type)
    # Fetch the entry from the database. There are two tables, one for OpenID Connect
    # login clients, and one for OAuth2 access token clients. They have some identical
    # columns, but ultimately they contain different data.

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

    client_config.freeze
  end
end   # class ClientDatabase

end   # module OAuth2
end   # module PuavoRest

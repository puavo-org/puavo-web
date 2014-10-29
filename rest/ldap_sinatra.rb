require_relative "./lib/error_codes"
require "sinatra/support"
require_relative "./auth"

module PuavoRest

# Abstract Sinatra base class which add ldap connection to instance scope
class LdapSinatra < Sinatra::Base
  helpers Sinatra::JSON
  helpers Sinatra::UserAgentHelpers
  set :json_encoder, :to_json
  set :show_exceptions, false
  set :dump_errors, false
  set :raise_errors, true

  def flog
    Thread.current[:fluent]
  end

  def flog=(logger)
    Thread.current[:fluent] = logger
  end

  # Respond with a text content
  def txt(text)
    content_type :txt
    halt 200, text.to_s
  end

  # In routes handlers use limit query string to slice arrays
  #
  # Example: /foos?limit=2
  #
  # @param a [Array] Array to slice
  def limit(a)
    if params["limit"]
      a[0...params["limit"].to_i]
    else
      a
    end
  end

end
end

require_relative "./ldap_hash"
require_relative "./lib/error_codes"
require_relative "./auth"

module PuavoRest

# Abstract Sinatra base class which add ldap connection to instance scope
class LdapSinatra < Sinatra::Base



  helpers Sinatra::JSON
  set :json_encoder, :to_json
  set :show_exceptions, false
  enable :logging

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

  # Render LdapHash::LdapHashError classes as nice json responses
  error JSONError do |err|
    halt err.http_code, json(err)
  end

  # class Err < Exception; end

  # error Err do |err|
  #   debugger; nil
  #   "foo"
  # end

  get "/err" do
    # raise Err, "Internal mesasge"
    "hello"
  end

  not_found do
    json({
      :error => {
        :message => "Not found"
      }
    })
  end

end
end

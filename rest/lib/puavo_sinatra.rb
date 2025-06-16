require "sinatra/support"
require_relative "./auth"

module PuavoRest

# Base class for all puavo-rest resources. Add common helper methods here
class PuavoSinatra < Sinatra::Base
  ROOT = File.dirname(File.dirname(__FILE__))
  helpers Sinatra::JSON
  helpers Sinatra::UserAgentHelpers
  set :json_encoder, :to_json
  set :show_exceptions, false
  set :dump_errors, false
  set :raise_errors, true
  set :root, ROOT

  # Get request specific {RestLogger} instance
  # @return RestLogger
  def rlog
    Thread.current[:logger]
  end

  # Set {RestLogger} instance for the request
  # @param logger [RestLogger]
  def rlog=(logger)
    Thread.current[:logger] = logger
  end

  # Respond with a text content
  # @param text [String]
  def txt(text)
    content_type :txt
    halt 200, text.to_s
  end

  # Try to parse JSON body and fallback to sinatra request.POST if not
  #
  # @return Hash
  def json_params
    return @json_body if @json_body

    if request.content_type.downcase.start_with?("application/json")
      @json_body = JSON.parse(request.body.read)
      return @json_body
    end

    return request.POST
  end

  # Convert comma separated attribute list to ruby Aarray
  #
  # @return Array
  def attribute_list
    return nil if params["attributes"].nil?

    params["attributes"].to_s.split(",")
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

  # Returns true if this user (username) is "super owner", ie. an owner user who has
  # been granted extra permissions. Usually these users are employees of the company
  # that makes Puavo.
  def super_owner?(name)
    begin
      # The filename is hardcoded, because the puavo-rest server dos already contain
      # some puavo-web's files, including this file, and it's always in /etc/puavo-web
      super_owners = File.read('/etc/puavo-web/super_owners.txt').split("\n")
    rescue StandardError => e
      rlog.error("ERROR: Can't query the super owner status: #{e}")
      super_owners = []
    end

    super_owners.include?(name)
  end

  # Generates a random request ID
  def make_request_id
    'ABCDEGIJKLMOQRUWXYZ12346789'.split('').sample(10).join
  end

end
end

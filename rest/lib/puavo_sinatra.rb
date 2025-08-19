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

  # Generates a random request ID
  def make_request_id
    'ABCDEGIJKLMOQRUWXYZ12346789'.split('').sample(10).join
  end

  def copyright
    CONFIG.fetch('branding', {}).fetch('copyright', '(Unknown copyright)')
  end

  def copyright_year
    CONFIG.fetch('branding', {}).fetch('copyright_year', '(Unknown copyright year)')
  end

  def copyright_with_year
    CONFIG.fetch('branding', {}).fetch('copyright_with_year', '(Unknown copyright)')
  end

  def manufacturer_name
    CONFIG.fetch('branding', {}).fetch('manufacturer', {}).fetch('name', '?')
  end

  def manufacturer_logo
    manufacturer = CONFIG.fetch('branding', {}).fetch('manufacturer', {})
    return '' if manufacturer.empty?

    "<a href=\"#{manufacturer['url']}\" target=\"_blank\"><img src=\"#{manufacturer['logo']}\" alt=\"#{manufacturer['alt_text']}\" title=\"#{manufacturer['title']}\" width=\"#{manufacturer['logo_width']}\" height=\"#{manufacturer['logo_height']}\"></a>"
  end

  def technical_support_email
    CONFIG.fetch('branding', {}).fetch('manufacturer', {}).fetch('technical_support_email', '?')
  end

  def technical_support_phone(international: false)
    phone = CONFIG.fetch('branding', {}).fetch('manufacturer', {}).fetch('technical_support_phone', {})
    return '' if phone.empty?

    phone.fetch(international ? 'international' : 'short', '?')
  end
end
end

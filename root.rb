require "ldap"
require "json"
require "multi_json"
require "sinatra/base"
require "sinatra/json"
require "base64"

require "debugger"
require "pry"

require "./credentials"
require "./base"
require "./external_files"

module PuavoRest
class Root < Sinatra::Base

  # @method get_root
  # @overload get "/"
  # Get hello message
  get "/" do
    "Hello :)"
  end


  # Post to foo
  # @return 
  post "/foo" do
  end

end
end

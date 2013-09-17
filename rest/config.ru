rest_dir = File.dirname File.expand_path __FILE__
require File.join rest_dir, "./config"
require File.join rest_dir, "./root"
require File.join rest_dir, "./lib/virtual_host_base"


class HideErrors
  def initialize(app)
    @app = app
  end

  def call(env)
    begin
      @app.call(env)
    rescue Exception => err
      time = Time.now.to_s
      puts "Error #{ err.class.name }: '#{ err }' at #{ time } (#{ time.to_i })"
      puts err.backtrace
      puts
      res = {
        "error" => {
          "code" => err.class.name,
          "time" => time,
          "message" => "Internal Server Error"
        }
      }.to_json
      [500, {'Content-Type' => 'application/json'}, [res]]
    end
  end
end

use HideErrors if ENV["RACK_ENV"] == "production"
use VirtualHostBase
run PuavoRest::Root

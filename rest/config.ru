rest_dir = File.dirname File.expand_path __FILE__
require "rack-timeout"
use Rack::Timeout
Rack::Timeout.timeout = 5

require File.join rest_dir, "./config"
require File.join rest_dir, "./root"

use VirtualHostBase
run PuavoRest::Root

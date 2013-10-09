rest_dir = File.dirname File.expand_path __FILE__
require File.join rest_dir, "./config"
require File.join rest_dir, "./root"

use HideErrors if ENV["RACK_ENV"] == "production"
use VirtualHostBase
run PuavoRest::Root

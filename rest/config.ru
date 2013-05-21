require "./rest/config"
require "./rest/root"
run PuavoRest::Root
# run Rack::Cascade.new([
#   PuavoRest::Root,
#   PuavoRest::ExternalFiles
# ])

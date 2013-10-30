
require 'socket'

require_relative "../../rest/lib/fluent"

FLOG = FluetWrap.new(
  "puavo-web",
  :hostname => Socket.gethostname,
  :version => "#{ PuavoUsers::VERSION } #{ PuavoUsers::GIT_COMMIT }"
)

FLOG.info "starting"

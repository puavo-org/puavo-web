
require 'socket'

require_relative "../../rest/lib/fluent"

FLOG = FluentWrap.new(
  "puavo-web",
  :hostname => Socket.gethostname,
  :version => "#{ PuavoUsers::VERSION } #{ PuavoUsers::GIT_COMMIT }"
)

FLOG.info "starting"

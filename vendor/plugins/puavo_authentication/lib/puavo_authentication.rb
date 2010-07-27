%w{ models controllers }.each do  |dir|
  path = File.join(File.dirname(__FILE__), 'app', dir)
  $LOAD_PATH << path
  ActiveSupport::Dependencies.load_paths << path
  ActiveSupport::Dependencies.load_once_paths.delete(path)
end

module Puavo
  autoload :Authentication, 'puavo/authentication'
  autoload :Connection, 'puavo/connection'
end

module PuavoAuthentication
  module Controllers
    autoload :Helpers, 'puavo_authentication/controllers/helpers'
  end
end

ActionController::Base.send :include, PuavoAuthentication::Controllers::Helpers
ActionController::Base.before_filter :ldap_setup_connection, :login_required

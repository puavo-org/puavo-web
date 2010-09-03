%w{ models controllers }.each do  |dir|
  path = File.join(File.dirname(__FILE__), 'app', dir)
  $LOAD_PATH << path
  ActiveSupport::Dependencies.load_paths << path
  ActiveSupport::Dependencies.load_once_paths.delete(path)
end

require 'puavo/authentication'
require 'puavo/connection'
require 'puavo_authentication/controllers/helpers'

ActionController::Base.send :include, PuavoAuthentication::Controllers::Helpers

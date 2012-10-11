%w{ models controllers }.each do  |dir|
  path = File.join(File.expand_path(__FILE__+'/../..'), 'app', dir)
  $LOAD_PATH << path
  ActiveSupport::Dependencies.load_paths << path
  ActiveSupport::Dependencies.load_once_paths.delete(path)
end

require 'puavo/authentication'
require 'puavo/connection'
require 'puavo/organisation'

require 'puavo_authentication/controllers/helpers'

ActionController::Base.send :include, PuavoAuthentication::Controllers::Helpers

begin
  Puavo::OAUTH_CONFIG = YAML.load_file("#{ RAILS_ROOT }/config/oauth.yml")
rescue Errno::ENOENT => e
  Puavo::OAUTH_CONFIG = nil
  puts "WARNING: " + e.to_s
end

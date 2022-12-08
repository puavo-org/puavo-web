require 'puavo/authentication'

Puavo::EXTERNAL_FILES = YAML.load_file("#{ PuavoUsers::config_dir }/puavo_external_files.yml") rescue nil
Puavo::EXTERNAL_LINKS = YAML.load_file("#{ PuavoUsers::config_dir }/puavo_external_links.yml") rescue nil

Puavo::CONFIG = YAML.load_file("#{ PuavoUsers::config_dir }/puavo_web.yml")

begin
  Puavo::SERVICES = YAML.load_file("#{ PuavoUsers::config_dir }/services.yml")
rescue Errno::ENOENT => e
  Puavo::SERVICES = nil
  puts "WARNING: " + e.to_s
end

REDIS_CONFIG = File.join(PuavoUsers::config_dir, 'redis.yml')
REDIS_CONNECTION = Redis.new YAML.load_file(REDIS_CONFIG).symbolize_keys

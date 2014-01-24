require 'puavo/authentication'

Puavo.available_languages = ['fi', 'en', 'sv']

Puavo::DEVICE_CONFIG = YAML.load_file("#{Rails.root}/config/puavo_devices.yml") rescue nil

Puavo::EXTERNAL_LINKS = YAML.load_file("#{Rails.root}/config/puavo_external_links.yml") rescue nil

Puavo::EXTERNAL_FILES = YAML.load_file("#{Rails.root}/config/puavo_external_files.yml") rescue nil

begin
  Puavo::SERVICES = YAML.load_file("#{Rails.root}/config/services.yml")
rescue Errno::ENOENT => e
  Puavo::SERVICES = nil
  puts "WARNING: " + e.to_s
end

REDIS_CONFIG = File.join(Rails.root, "config", "redis.yml")
REDIS_CONNECTION = Redis.new YAML.load_file(REDIS_CONFIG).symbolize_keys

require 'puavo/authentication'

Puavo.available_languages = ['fi', 'en', 'sv']

Puavo::DEVICE_CONFIG = YAML.load_file("#{Rails.root}/config/puavo_devices.yml") rescue nil

Puavo::EXTERNAL_LINKS = YAML.load_file("#{Rails.root}/config/puavo_external_links.yml") rescue nil

begin
  Puavo::OAUTH_CONFIG = YAML.load_file("#{ Rails.root }/config/oauth.yml")
rescue Errno::ENOENT => e
  Puavo::OAUTH_CONFIG = nil
  puts "WARNING: " + e.to_s
end

require "monkeypatches"

Puavo.available_languages = ['fi', 'en', 'sv']

Puavo::OAUTH_CONFIG = YAML.load_file("#{ RAILS_ROOT }/config/oauth.yml")

Puavo::DEVICE_CONFIG = YAML.load_file("#{RAILS_ROOT}/config/puavo_devices.yml") rescue nil

Puavo::EXTERNAL_LINKS = YAML.load_file("#{RAILS_ROOT}/config/puavo_external_links.yml") rescue nil

require "monkeypatches"

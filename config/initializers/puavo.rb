Puavo.available_languages = ['fi', 'en', 'sv']

Puavo::DEVICE_CONFIG = YAML.load_file("#{RAILS_ROOT}/config/puavo_devices.yml") rescue nil

Puavo.available_languages = ['fi', 'en', 'sv']

Puavo::DEVICE_CONFIG = YAML.load_file("#{RAILS_ROOT}/config/puavo_devices.yml") rescue nil

Puavo::EXTERNAL_LINKS = YAML.load_file("#{RAILS_ROOT}/config/puavo_external_links.yml") rescue nil

begin
  Puavo::CONFIGURATION_FILES = YAML.load_file("#{RAILS_ROOT}/config/configuration_files.yml")
rescue Errno::ENOENT
  RAILS_DEFAULT_LOGGER.warn "No such file or directory: "#{RAILS_ROOT}/config/configuration_files.ym""
end


require "monkeypatches"

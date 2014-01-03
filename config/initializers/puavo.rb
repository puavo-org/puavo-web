require 'puavo/authentication'

Puavo.available_languages = ['fi', 'en', 'sv']

Puavo::DEVICE_CONFIG = YAML.load_file("#{Rails.root}/config/puavo_devices.yml") rescue nil

Puavo::EXTERNAL_LINKS = YAML.load_file("#{Rails.root}/config/puavo_external_links.yml") rescue nil

Puavo::EXTERNAL_FILES = YAML.load_file("#{Rails.root}/config/puavo_external_files.yml") rescue nil

begin
  Puavo::OAUTH_CONFIG = YAML.load_file("#{ Rails.root }/config/oauth.yml")
rescue Errno::ENOENT => e
  Puavo::OAUTH_CONFIG = nil
  puts "WARNING: " + e.to_s
end

begin
  Puavo::SERVICES = YAML.load_file("#{Rails.root}/config/services.yml")
rescue Errno::ENOENT => e
  Puavo::SERVICES = nil
  puts "WARNING: " + e.to_s
end

begin
  Puavo::RESQUE_WORKER_PRIVATE_KEY =
    OpenSSL::PKey::RSA.new( 
      File.read(
        File.join(Rails.root, "config", "resque_worker_private_key") ) )
rescue Errno::ENOENT => e
  Puavo::RESQUE_WORKER_PRIVATE_KEY = nil
end

begin
  Puavo::RESQUE_WORKER_PUBLIC_KEY =
    OpenSSL::PKey::RSA.new( 
      File.read(
        File.join(Rails.root, "config", "resque_worker_public_key") ) )
rescue Errno::ENOENT => e
  Puavo::RESQUE_WORKER_PUBLIC_KEY = nil
end

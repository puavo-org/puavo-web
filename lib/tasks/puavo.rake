require 'tempfile'
require 'puavo/etc'

namespace :puavo do
  desc "Set config/database.yml"
  task :database do
    cp "config/database.yml.development", "config/database.yml"
  end

  desc "Set config/ldap.yml"
  task :ldap do
    cp "config/ldap.yml.development", "config/ldap.yml"
  end

  desc "Set config/oauth.yml"
  task :oauth do
    cp "config/oauth.yml.development", "config/oauth.yml"
  end

  desc "Set config/organisation.yml"
  task :organisation do
    @hostname = (`hostname -s`).strip + ".#{PUAVO_ETC.topdomain}"
    template = File.read("config/organisations.yml.development")
    parse_file = ERB.new(template, 0, "%<>")

    tempfile = Tempfile.open("organisation.yml")
    tempfile.puts parse_file.result
    tempfile.close

    cp tempfile.path, "config/organisations.yml"
    tempfile.delete
  end

  desc "Set config/puavo_device.yml"
  task :puavo_devices do
    cp "config/puavo_devices.yml.development", "config/puavo_devices.yml"
  end

  desc "Set all Puavo configuration files (development)"
  task :configuration => [:database,
                          :ldap,
                          :puavo_devices,
                          :organisation]

end

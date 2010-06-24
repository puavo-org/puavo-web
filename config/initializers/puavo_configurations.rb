configurations_file = File.join(RAILS_ROOT, 'config', 'puavo.yml')
        
if File.exist?(configurations_file)
  Puavo.configurations = YAML.load(ERB.new(IO.read(configurations_file)).result)
end

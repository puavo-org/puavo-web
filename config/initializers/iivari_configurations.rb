configurations_file = File.join(RAILS_ROOT, 'config', 'iivari.yml')
        
if File.exist?(configurations_file)
  Iivari.configurations = YAML.load(ERB.new(IO.read(configurations_file)).result)
end

# External integrations stuff

# Integration definitions simply define a "pretty" (human-readable) name
# and a type for each third-party integration. Schedules and other details
# are stored elsewhere.
class IntegrationDefinition
  attr_reader :name
  attr_reader :pretty_name
  attr_reader :type

  def initialize(name, pretty_name, type)
    unless [:in, :out, :inout, :login, :password, :other].include?(type)
      raise "Invalid integration type \"#{type}\""
    end

    @name = name
    @pretty_name = pretty_name
    @type = type
  end
end

Puavo::INTEGRATION_DEFINITIONS = {}

name = "#{Rails.root}/config/integrations.yml"

if File.exists?(name)
  begin
    data = YAML.load_file(name)
  rescue StandardError => e
    puts "Could not load file \"#{name}\": #{e}"
    data = {}
  end

  data.fetch('integration_definitions', {}).each do |name, definition|
    if Puavo::INTEGRATION_DEFINITIONS.include?(name)
      raise "Integration name \"#{name}\" used more than once, names must be unique"
    end

    unless definition.include?('name')
      raise "Integration \"#{name}\" has no pretty name"
    end

    unless definition.include?('type')
      raise "Integration \"#{name}\" has no type"
    end

    case definition['type']
      when 'in'
        type = :in

      when 'out'
        type = :out

      when 'inout'
        type = :inout

      when 'login'
        type = :login

      when 'password'
        type = :password

      when 'other'
        type = :other
    else
      raise "Integration \"#{name}\" has an unknown type \"#{definition['type']}\""
    end

    Puavo::INTEGRATION_DEFINITIONS[name] = IntegrationDefinition.new(name, definition['name'], type)
  end
end

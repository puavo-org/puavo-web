# These monkey patches are applied during Rails boot up. We should eventually
# get rid of all of these since these must all reviewed when gem versions are
# updated.

# Logging helper. Rails.logger does not print anything this early to
# stdout/stderr on the Rails boot process

def log(msg)
  $stderr.puts "#{ msg }\n"
  Rails.logger.warn msg
end

log "Monkey patching https://github.com/activeldap/activeldap/pull/52 to active-ldap."

module ActiveLdap
  module Validations
    def validate_ldap_values
      entry_attribute.schemata.each do |name, attribute|
        value = attribute.binary? ? self[name].try(:force_encoding, 'ASCII-8BIT') : self[name]
        next if self.class.blank_value?(value)
        validate_ldap_value(attribute, name, value)
      end
    end
  end
end

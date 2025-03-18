Rails.autoloaders.main.inflector.inflect('mfa' => 'MFA')

# For some reason, I cannot inflect MacAddress into MACAddress?
# Adding an inflection here and running "bin/rails zeitwerk:check"
# still complains:
#   expected file app/models/mac_address.rb to define constant MacAddress
# I guess I'm doing it wrong and I just don't see it

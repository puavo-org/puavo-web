# These monkey patches are applied during Rails boot up. We should eventually
# get rid of all of these since these must all reviewed when gem versions are
# updated.


# Logging helper. RAILS_DEFAULT_LOGGER does not print anything this early to
# stdout/stderr on the Rails boot process
def log(msg)
  $stderr.puts "#{ msg }\n"
  RAILS_DEFAULT_LOGGER.warn msg
end








log "Monkey patching LDAP schema caches to activeldap. Expecting version 1.2.4."
# The schemas are fetched on every request which useless, because the schemas
# changes very rarely. This monkey patch will save about 50ms on every request
# made to Puavo.
# See: https://github.com/activeldap/activeldap/blob/1.2.4/lib/active_ldap/adapter/base.rb#L116
require "active_ldap/adapter/base"
class ActiveLdap::Adapter::Base
  alias orig_schema schema
  def schema
    @schema ||= Rails.cache.fetch "ldap_schemas" do
      orig_schema
    end
  end
end

puts "Monkey patching LDAP schema caches to activeldap. Expecting version 3.2.2"
# The schemas are fetched on every request which useless, because the schemas
# changes very rarely. This monkey patch will save about 50ms on every request
# made to Puavo.
# See: https://github.com/activeldap/activeldap/blob/3.2.2/lib/active_ldap/adapter/base.rb#L117-L145
require "active_ldap/adapter/base"
class ActiveLdap::Adapter::Base
  alias orig_schema schema
  def schema(options=nil)
    @schema ||= Rails.cache.fetch "ldap_schemas:#{ options.to_s }" do
      orig_schema(options)
    end
  end
end

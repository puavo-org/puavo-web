# These monkey patches are applied during Rails boot up. We should eventually
# get rid of all of these since these must all reviewed when gem versions are
# updated.


# Logging helper. RAILS_DEFAULT_LOGGER does not print anything this early to
# stdout/stderr on the Rails boot process
def log(msg)
  $stderr.puts "#{ msg }\n"
  RAILS_DEFAULT_LOGGER.warn msg
end




log "Monkey patching https://github.com/ruby-ldap/ruby-net-ldap/pull/42 to net-ldap. Expecting version 0.2.2."
# Backport above pull request to net-ldap version 0.2.2. This should be removed
# when it is merged to upstream and released.
require "net-ldap"
class Net::LDAP::Filter::FilterParser
  def parse_filter_branch(scanner)
    scanner.scan(/\s*/)
    if token = scanner.scan(/[-\w:.]*[\w]/)
      scanner.scan(/\s*/)
      if op = scanner.scan(/<=|>=|!=|:=|=/)
        scanner.scan(/\s*/)
        # Filter value matching. Use negation to get all allowed characters
        # including escaped characters defined in
        # http://tools.ietf.org/html/rfc2254#page-5
        if value = scanner.scan(/[^\(\)\0]+/)
          # With previous scan the string might still contain some
          # unwanted '\' characters. Bail out if there is one.
          no_escaped_chars = value.gsub(/\\[a-fA-F\d]{2}/, "")
          return if no_escaped_chars.include?("\\")
          # 20100313 AZ: Assumes that "(uid=george*)" is the same as
          # "(uid=george* )". The standard doesn't specify, but I can find
          # no examples that suggest otherwise.
          value.strip!
          case op
          when "="
            Net::LDAP::Filter.eq(token, value)
          when "!="
            Net::LDAP::Filter.ne(token, value)
          when "<="
            Net::LDAP::Filter.le(token, value)
          when ">="
            Net::LDAP::Filter.ge(token, value)
          when ":="
            Net::LDAP::Filter.ex(token, value)
          end
        end
      end
    end
  end
  private :parse_filter_branch
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

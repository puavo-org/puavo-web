
# Simple class for profiling LDAP Queries
#
# Set LDAP_PROFILER=1 environment variable to enable query profiling.
#
# Query time are printed to stdout after.
#
class LdapSearchProfiler
  require "colorize"

  def initialize(key)
    @key = key
  end

  class Timer
    attr_accessor :duration
    def initialize
      @started = Time.now
      @duration = 0
    end

    def stop
      if ENV["LDAP_PROFILER"]
        @duration = (Time.now - @started).to_f * 1000
        return @duration
      end
    end
  end

  def start
    return Timer.new
  end

  def profile(dn, filter, ldap_base, attributes, &block)
    timer = Timer.new

    msg = "-"*80
    msg += "\\\n"
    msg += "Bind dn: #{ dn.inspect }\n"
    msg += "Filter: #{ filter.inspect }\n"
    msg += "base: #{ ldap_base.inspect }\n"
    msg += "Attributes: #{ Array(attributes).join(",") }\n"

    begin
      block.call
    ensure
      duration = timer.stop()
      count(timer)
      msg += "Completed in #{ duration } ms\n"
      msg += "-"*80
      msg += "/"
      puts(msg.colorize(:blue))
    end
  end

  # Create profiling methods only when profiling is activated
  if ENV["LDAP_PROFILER"]
    puts(("#"*40).colorize(:blue))
    puts "LDAP profiling active!".colorize(:blue)
    puts(("#"*40).colorize(:blue))

    # Query data is stored to thread local. This should be cleared before usage
    def store
      Thread.current["profiler:#{ @key }"] ||= {}
    end

    def reset
      Thread.current["profiler:#{ @key }"] = nil
      store[:queries] = []
    end

    def print_search_count(target)
      duration = store[:queries].reduce(0){ |memo, q| memo + q.duration }

      puts "Did #{ store[:queries].size } LDAP queries in #{ duration }ms for #{ target }".colorize(:blue)
      puts(("#"*80).colorize(:blue))
    end

    def count(timer)
      store[:queries].push(timer)
    end


  else
    # Just dummy out profiling calls when profiling is not active
    def method_missing(*); end
  end
end

# Add singleton instance for LdapModel
class LdapModel
  PROF = LdapSearchProfiler.new "ldapsearch"
end


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
    def initialize
      @started = Time.now
    end

    def stop(msg="")
      if ENV["LDAP_PROFILER"]
        diff = Time.now - @started
        puts "#{ msg } in #{ diff.to_f * 1000 } ms".colorize(:blue)
      end
    end
  end

  def start
    return Timer.new
  end

  # Create profiling methods only when profiling is activated
  if ENV["LDAP_PROFILER"]
    puts "#"*40
    puts "LDAP profiling active!"
    puts "#"*40

    # Query data is stored to thread local. This should be cleared before usage
    def store
      Thread.current["profiler:#{ @key }"] ||= {}
    end

    def reset
      Thread.current["profiler:#{ @key }"] = nil
    end

    def print_search_count(target)
      puts "Did #{ store[:query_count] } ldap queries in #{ target }".colorize(:blue)
    end

    def count
      store[:query_count] ||= 0
      store[:query_count] += 1
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


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
    reset
  end

  class Timer
    attr_accessor :duration
    def initialize
      @started = Time.now
      @duration = 0
    end

    def stop(msg="")
      if ENV["LDAP_PROFILER"]
        color = :blue
        @duration = (Time.now - @started).to_f * 1000
        puts "#{ msg } in #{ @duration } ms".colorize(color)
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
      store[:queries] = []
    end

    def print_search_count(target)
      duration = store[:queries].reduce(0){ |memo, q| memo + q.duration }

      puts "Did #{ store[:queries].size } LDAP queries in #{ duration }ms for #{ target }".colorize(:blue)
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

# Logging helper. RAILS_DEFAULT_LOGGER does not print anything this early to
# stdout/stderr on the Rails boot process
def log(msg)
  $stderr.puts "#{ msg }\n"
  RAILS_DEFAULT_LOGGER.warn msg
end

log "Add delete method to ActiveRecord::Errors class. "
# Delete method is implemented on the 3.2.1 version of the Rails. This should be remove
# when Rails is uptodate
module ActiveRecord
  class Errors
    def delete(attribute)
      @errors.delete(attribute.to_s)
    end
  end
end

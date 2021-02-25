class RestLogger
  # @param base_attrs [Hash] Data to be added for each log message
  def initialize(base_attrs)
    @logger = Logger.new(STDOUT)
    @base_attrs = clean(base_attrs)
  end

  # Create a new child logger. The child will inherit base_attrs from the parent.
  # @param more_attrs [Hash] Data to be added for each log message
  def merge(more_attrs=nil)
    RestLogger.new(
      @base_attrs.merge(more_attrs || {})
    )
  end

  # Shortcut for #log(:info, msg)
  # @see #log
  def info(message)
    log("info", message)
  end

  # Shortcut for #log(:warn, msg)
  # @see #log
  def warn(message)
    log("warn", message)
  end

  # Shortcut for #log(:error, msg)
  # @see #log
  def error(message)
    log("error", message)
  end

  private

  # Log a message
  #
  # @param level [Symbol] `:info`, `:warn` or `:error`
  # @param message [String] message for humans
  # @param attrs [hash] Data to be added with the message
  def log(level, message)
    return unless message

    # Prevent the puavo-rest test runner from logging messages
    return if !((ENV["RACK_ENV"] != "test") || (ENV["RAILS_ENV"] != "test"))

    record = {
      :meta => clean(@base_attrs)
    }

    begin
      @logger.send(level, human_readable_msg(message, record))
    rescue StandardError => e
      STDERR.puts "FATAL: Failed to log message: #{message}: #{e}"
    end
  end

  def human_readable_msg(msg, record, show_full_record=false)
    meta    = (record && record[:meta]) || nil
    request = (meta && record[:meta][:request]) || nil

    hostname_fqdn = (request && request[:client_hostname]) || '?'

    client_ip    = (request && request[:ip])              || '?'
    hostname     = hostname_fqdn.split('.')[0]            || '?'
    method       = (request && request[:method])          || '(METHOD?)'
    organisation = (meta    && meta[:organisation_key])   || '?'

    # Use only path here instead of the full url,
    # because the full url may contain sensitive parameters.
    path = (request && request[:path]) || '(PATH?)'

    msg_no_newlines = msg.to_s.chomp.gsub(/\n/, ' / ')
    message = "#{ method } #{ path } from #{ hostname }/#{ client_ip } (#{ organisation }) :: #{ msg_no_newlines }"

    if !request || !meta
      message = "#{ message }, #{ record.to_json }"
    end

    message
  end

  MAX_SIZE = 1024 * 512
  def truncate_large(val)
    return val if !val.kind_of?(String)
    if val.size > MAX_SIZE
      val.slice(0, MAX_SIZE) << "[TRUNCATED #{ val.size - MAX_SIZE } bytes]"
    else
      val
    end
  end

  def filter_passwords(val)
    return val if !val.kind_of?(Hash)
    val = val.dup
    val.each do |k, v|
      # Sensor keys that contain word password
      if k.to_s.include?("password")
        val[k] = "[FILTERED]"
      end
    end
    val
  end

  def clean(val)
    val = truncate_large(val)
    val = filter_passwords(val)

    if val.kind_of?(Array)
      val = val.map do |val|
        clean(val)
      end
    end

    if val.kind_of?(Hash)
      val = val.dup
      val.each do |k, v|
        val[k] = clean(v)
      end
    end

    val
  end

end

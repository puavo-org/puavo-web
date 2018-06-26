
require 'fluent-logger'

Fluent::Logger::FluentLogger.open(nil, :host=>'localhost', :port=>24224)

# Small wrapper for fluent-logger gem. Most notably this wrapper filters out
# all data keys with `password` string
class FluentWrap

  # @param tag [String] Fluent tag
  # @param base_attrs [Hash] Data to be added for each log message
  # @param logger [Object] Fluent logger object. Can be set for mocking purposes for testing
  def initialize(tag, base_attrs, fluent_logger=Fluent::Logger, sinatra_logger=nil)
    @tag = tag
    @fluent_logger = fluent_logger
    @sinatra_logger = sinatra_logger
    @base_attrs = clean(base_attrs)
  end

  # Log a message
  #
  # @param level [Symbol] `:info`, `:warn` or `:error`
  # @param msgtag [String] fluent tag-like message
  # @param message [String] message for humans
  # @param attrs [hash] Data to be added with the message
  def log(level, msgtag, message=nil, attrs=nil)
    if [:msg, :meta, :level].include?(msgtag)
      raise "Illegal fluentd message key: #{ msgtag }"
    end

    record = {
      :msg  => msgtag, # for legacy elasticsearch support
      :meta => clean(@base_attrs),
    }

    record[:meta][:level] = level

    # Write attrs under a key defined by msgtag to avoid type errors in
    # elasticsearch
    record[msgtag] = clean(attrs) if attrs

    if message then
      if ENV["FLUENTD_STDOUT"] || (ENV["RACK_ENV"] != "test") || (ENV["RAILS_ENV"] != "test") then
        begin
          if !%w(info warn error).include?(level) then
            raise 'Unsupported log level method'
          end
          if @sinatra_logger.nil?
            raise 'Sinatra logger object is not set'
          end

          @sinatra_logger.send(level, human_readable_msg(message, record))

        rescue StandardError => e
          #STDERR.puts "Failed to log message: #{ record.inspect } :: #{ e }"
        end
      end
    end

    if msgtag then
      @fluent_logger.post(@tag, record)
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

    if !msg.kind_of?(String) then
      raise 'Message is not a string'
    end
    msg_no_newlines = msg.chomp.gsub(/\n/, ' / ')
    message = "#{ method } #{ path } from #{ hostname }/#{ client_ip } (#{ organisation }) :: #{ msg_no_newlines }"

    if !request || !meta || show_full_record then
      message = "#{ message } :::: #{ record.to_json }"
    end

    message
  end

  # Shortcut for #log(:info, msg)
  # @see #log
  def info(msgtag, message=nil, attrs=nil)
    log("info", msgtag, message, attrs)
  end

  # Shortcut for #log(:warn, msg)
  # @see #log
  def warn(msgtag, message=nil, attrs=nil)
    log("warn", msgtag, message, attrs)
  end

  # Shortcut for #log(:error, msg)
  # @see #log
  def error(msgtag, message=nil, attrs=nil)
    log("error", msgtag, message, attrs)
  end

  # Create new child logger. The child will inherit base_attrs from the parent
  # @param more_attrs [Hash] Data to be added for each log message
  # @param new_logger [Object] Change log logger instance 
  # @return FluentWrap
  def merge(more_attrs=nil, new_fluent_logger=nil, new_sinatra_logger=nil)
    FluentWrap.new(
      @tag,
      @base_attrs.merge(more_attrs || {}),
      new_fluent_logger || @fluent_logger,
      new_sinatra_logger || @sinatra_logger,
    )
  end

  private

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


require 'fluent-logger'

Fluent::Logger::FluentLogger.open(nil, :host=>'localhost', :port=>24224)

# Small wrapper for fluent-logger gem. Most notably this wrapper filters out
# all data keys with `password` string
class FluentWrap

  # @param tag [String] Fluent tag
  # @param base_attrs [Hash] Data to be added for each log message
  # @param logger [Object] Fluent logger object. Can be set for mocking purposes for testing
  def initialize(tag, base_attrs, logger=Fluent::Logger)
    @tag = tag
    @logger = logger
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
          STDERR.puts human_readable_msg(message, record)
        rescue StandardError => e
          STDERR.puts "Failed to log message: #{ record.inspect } :: #{ e }"
        end
      end
    end

    if msgtag then
      @logger.post(@tag, record)
    end
  end

  def human_readable_msg(msg, record, show_full_record=false)
    meta    = (record && record[:meta]) || nil
    request = (meta && record[:meta][:request]) || nil

    url          = (request && request[:url])             || '(URL?)'
    method       = (request && request[:method])          || '(METHOD?)'
    hostname     = (request && request[:client_hostname]) || '?'
    client_ip    = (request && request[:ip])              || '?'
    organisation = (meta    && meta[:organisation_key])   || '?'
    short_req_id = ((meta   && meta[:req_uuid])           || '?')[0..7]

    message = "#{ method } #{ url } from #{ hostname }/#{ client_ip } (#{ organisation }) :: [#{ short_req_id }] #{ msg }"

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
  def merge(more_attrs=nil, new_logger=nil)
    FluentWrap.new(
      @tag,
      @base_attrs.merge(more_attrs || {}),
      new_logger || @logger
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

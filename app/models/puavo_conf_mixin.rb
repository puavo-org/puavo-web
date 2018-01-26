module PuavoConfMixin
  def puavoConf=(puavoconf_string)
    puavoconf_data = parse_as_json(puavoconf_string)
    return if puavoconf_data.nil?

    if !validate_puavoconf_data(puavoconf_data) then
      logger.warn 'not storing invalid puavoconf-data'
      return
    end

    set_attribute('puavoConf', puavoconf_data.to_json)
  end

  def parse_as_json(string)
    begin
      data = JSON.parse(string)
    rescue JSON::ParserError => e
      logger.warn "could not parse '#{ string }' as JSON: #{ e.message }"
      return nil
    end

    data
  end

  def validate_puavoconf_data(puavoconf_data)
    return false unless puavoconf_data.kind_of?(Hash)

    puavoconf_data.all? do |k,v|
      k.kind_of?(String) \
        && (v.kind_of?(String) || v.kind_of?(Integer) \
              || v == false || v == true)
    end
  end
end

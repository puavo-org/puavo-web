module PuavoConfMixin
  def puavoConfString
    Array(get_attribute('puavoConf')).first
  end

  def puavoConfString=(puavoconf_string)
    begin
      puavoconf_data = JSON.parse(puavoconf_string)
    rescue StandardError => e
      return
    end

    puavoConf = puavoconf_data
  end

  def puavoConf
    puavoconf_data = JSON.parse(puavoConfString) rescue {}

    if !validate_puavoconf_data(puavoconf_data) then
      puavoconf_data = {}
    end

    puavoconf_data
  end

  def puavoConf=(puavoconf_data)
    if !validate_puavoconf_data(puavoconf_data) then
      return
    end

    set_attribute('puavoConf', puavoconf_data.to_json)
  end

  def validate_puavoconf_data(puavoconf)
    return false unless puavoconf.kind_of?(Hash)

    puavoconf.all? do |k,v|
      k.kind_of?(String) \
        && (v.kind_of?(String) || v.kind_of?(Integer) \
              || v == false || v == true)
    end
  end
end

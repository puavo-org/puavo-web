module PuavoConfMixin
  def validate_puavoconf
    puavoconf_string = self.puavoConf.to_s
    return if puavoconf_string.empty?

    begin
      puavoconf_data = JSON.parse(puavoconf_string)
    rescue JSON::ParserError => e
      errors.add(:puavoConf,
                 I18n.t('activeldap.errors.messages.puavoconf.not_json'))
      return
    rescue StandardError => e
      errors.add(:puavoConf,
                 I18n.t('activeldap.errors.messages.puavoconf.unknown_json_error'))
      return
    end

    unless puavoconf_data.kind_of?(Hash) then
      errors.add(:puavoConf,
                 I18n.t('activeldap.errors.messages.puavoconf.not_a_hash'))
      return
    end

    types_ok = puavoconf_data.all? do |k,v|
                 k.kind_of?(String) \
                   && (v.kind_of?(String) || v.kind_of?(Integer) \
                         || v == false || v == true)
               end
    unless types_ok then
      errors.add(:puavoConf,
                 I18n.t('activeldap.errors.messages.puavoconf.unsupported_value_types'))
      return
    end
  end
end

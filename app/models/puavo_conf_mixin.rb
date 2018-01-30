module PuavoConfMixin
  def validate_puavoconf
    # XXX localize error messages

    begin
      puavoconf_data = JSON.parse( get_attribute(:puavoConf) )
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

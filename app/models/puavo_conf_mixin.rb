# frozen_string_literal: true

module PuavoConfMixin
  def validate_puavoconf
    puavoconf_string = self.puavoConf.to_s
    return if puavoconf_string.empty?

    begin
      puavoconf_data = JSON.parse(puavoconf_string)
    rescue JSON::ParserError
      errors.add(:puavoConf, I18n.t('activeldap.errors.messages.puavoconf.not_json'))
      return
    rescue StandardError
      errors.add(:puavoConf, I18n.t('activeldap.errors.messages.puavoconf.unknown_json_error'))
      return
    end

    unless puavoconf_data.is_a?(Hash)
      errors.add(:puavoConf, I18n.t('activeldap.errors.messages.puavoconf.not_a_hash'))
      return
    end

    types_ok = puavoconf_data.all? do |k, v|
      k.is_a?(String) && (v.is_a?(String) || v.is_a?(Integer) || v == false || v == true)
    end

    return if types_ok

    errors.add(:puavoConf, I18n.t('activeldap.errors.messages.puavoconf.unsupported_value_types'))
  end
end

# frozen_string_literal: true

module BooleanAttributes
  def puavoAllowGuest=(boolean)
    set_attribute('puavoAllowGuest', fix_boolean_value(boolean))
  end

  def puavoPersonalDevice=(boolean)
    set_attribute('puavoPersonalDevice', fix_boolean_value(boolean))
  end

  def puavoAutomaticImageUpdates=(boolean)
    set_attribute('puavoAutomaticImageUpdates', fix_boolean_value(boolean))
  end

  private

  def fix_boolean_value(value)
    if [true, 'true', 'TRUE'].include?(value)
      true
    elsif [false, 'false', 'FALSE'].include?(value)
      false
    else
      nil
    end
  end
end

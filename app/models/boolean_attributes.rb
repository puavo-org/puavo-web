module BooleanAttributes
  
  def puavoAllowGuest=(boolean)
    value = fix_boolean_value(boolean)
    set_attribute("puavoAllowGuest", value)
  end

  def puavoPersonalDevice=(boolean)
    value = fix_boolean_value(boolean)
    set_attribute("puavoPersonalDevice", value)
  end

  def puavoAutomaticImageUpdates=(boolean)
    value = fix_boolean_value(boolean)
    set_attribute("puavoAutomaticImageUpdates", value)
  end

  private

  def fix_boolean_value(value)
    if value == true || value == "true" || value == "TRUE"
      return "TRUE"
    elsif value == false || value == "false" || value == "FALSE"
      return "FALSE"
    else
      return nil
    end
  end

end

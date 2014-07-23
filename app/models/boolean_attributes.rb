module BooleanAttributes
  
  def puavoAllowGuest=(boolean)
    if boolean == true || boolean == "true" || boolean == "TRUE"
      boolean = "TRUE"
    elsif boolean == false || boolean == "false" || boolean == "FALSE"
      boolean = "FALSE"
    else
      boolean = nil
    end
    set_attribute("puavoAllowGuest", boolean)
  end

  def puavoPersonalDevice=(boolean)
    if boolean == true || boolean == "true" || boolean == "TRUE"
      boolean = "TRUE"
    elsif boolean == false || boolean == "false" || boolean == "FALSE"
      boolean = "FALSE"
    else
      boolean = nil
    end
    set_attribute("puavoPersonalDevice", boolean)
  end

  def puavoAutomaticImageUpdates=(boolean)
    # FIXME refactor!
    if boolean == true || boolean == "true" || boolean == "TRUE"
      boolean = "TRUE"
    elsif boolean == false || boolean == "false" || boolean == "FALSE"
      boolean = "FALSE"
    else
      boolean = nil
    end
    set_attribute("puavoAutomaticImageUpdates", boolean)
  end

end

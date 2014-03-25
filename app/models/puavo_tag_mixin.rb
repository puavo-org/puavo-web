module PuavoTagMixin

  def puavoTag
    Array(get_attribute( "puavoTag")).join(" ")
  end

  def puavoTag=(tag_string)
    if tag_string.class == Array
      set_attribute( "puavoTag", tag_string )
    elsif tag_string.class == String
      set_attribute( "puavoTag", tag_string.split(" ") )
    end
  end

  def puavoTag_before_type_cast
    self.puavoTag
  end

end
